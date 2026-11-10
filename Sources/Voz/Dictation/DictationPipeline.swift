import AppKit

@MainActor
final class DictationPipeline {
    private let engine: SpeechEngine
    private let cleaner: TextCleaner
    private let settings: AppSettings
    private let history: HistoryStore
    private let output: TextOutput
    private let editObserver: EditObserver
    private let vocabularyLearner: VocabularyLearner
    private let analytics: Analytics
    private let extensions: ExtensionService
    private let telemetry: TelemetryReporter

    init(
        engine: SpeechEngine,
        cleaner: TextCleaner,
        settings: AppSettings,
        history: HistoryStore,
        output: TextOutput,
        editObserver: EditObserver,
        vocabularyLearner: VocabularyLearner,
        analytics: Analytics,
        extensions: ExtensionService,
        telemetry: TelemetryReporter
    ) {
        self.engine = engine
        self.cleaner = cleaner
        self.settings = settings
        self.history = history
        self.output = output
        self.editObserver = editObserver
        self.vocabularyLearner = vocabularyLearner
        self.analytics = analytics
        self.extensions = extensions
        self.telemetry = telemetry
    }

    func collectLearnedWords() {
        editObserver.collect()
    }

    func makeStreaming(app: Task<HostApp, Never>) -> StreamingDictation {
        let plan = CleanupPlan(prompt: settings.cleanupPrompt, mode: settings.cleanupMode)
        let vocabulary = history.vocabulary.wordsOrLogged()
        return StreamingDictation(
            transcribe: applying(history.vocabulary.rulesOrLogged(), to: transcriber(app: app, vocabulary: vocabulary)),
            cleaner: cleaner,
            vocabulary: vocabulary,
            plan: Task { [extensions] in await extensions.cleanupPlan(plan, app: await app.value) },
            languages: settings.languages,
            cleanupEnabled: settings.cleanupEnabled,
            steps: settings.cleanupSteps,
            extensions: extensions.cleanupExtensions(model: settings.cleanupModel, app: app)
        )
    }

    private func applying(_ rules: [VocabularyRule], to transcribe: @escaping SegmentTranscriber) -> SegmentTranscriber {
        guard !rules.isEmpty else { return transcribe }
        return { samples in
            let result = try await transcribe(samples)
            return TranscriptionResult(
                text: VocabularyRule.apply(rules, to: result.text),
                audioSeconds: result.audioSeconds,
                processingSeconds: result.processingSeconds,
                model: result.model
            )
        }
    }

    private func transcriber(app: Task<HostApp, Never>, vocabulary: [String]) -> SegmentTranscriber {
        let selected = settings.speechModel
        let local = settings.localSpeechModel
        return { [engine, extensions] samples in
            guard extensions.hasSpeechModel(selected) else {
                return try await engine.transcribe(samples, model: local, vocabulary: vocabulary)
            }
            let started = ContinuousClock.now
            guard let text = await extensions.transcribe(samples, model: selected, app: await app.value) else {
                Log.extensions.error("Speech model \(selected, privacy: .public) failed, using \(local.rawValue, privacy: .public)")
                Analytics.report(.speechExtensionFailed)
                return try await engine.transcribe(samples, model: local, vocabulary: vocabulary)
            }
            let elapsed = Double((ContinuousClock.now - started).wholeMilliseconds) / 1000
            return TranscriptionResult(text: text, audioSeconds: Double(samples.count) / RecordingFilter.sampleRate, processingSeconds: elapsed, model: selected)
        }
    }

    func run(_ recording: Recording, streaming session: StreamingDictation, released: ContinuousClock.Instant) async -> Dictation.Outcome {
        extensions.recorded(recording.samples, app: recording.app)
        do {
            guard let transcript = try await session.finish(samples: recording.samples, released: released) else {
                Log.app.notice("Transcription was empty")
                DebugLog.shared.write("dictation", ["outcome": "empty", "app": recording.app.name ?? ""])
                analytics.capture(.dictationDiscarded(reason: .emptyTranscript))
                return .discarded
            }
            Log.app.notice("Transcribed \(transcript.audioSeconds, format: .fixed(precision: 1))s with \(transcript.model): \(transcript.segmentCount) segments, \(transcript.cleanedInTime) of \(transcript.unitCount) sentence groups cleaned in time, tail STT \(transcript.sttMs) ms, cleanup wait \(transcript.cleaned.milliseconds) ms")
            let delivery = await extensions.prepare(transcript.cleaned.text, raw: transcript.raw, app: recording.app)
            let insertStarted = ContinuousClock.now
            if recording.inserts, !delivery.text.isEmpty {
                await output.deliver(delivery.text)
                if settings.insertIntoApp { editObserver.observe(inserted: delivery.text) }
                extensions.inserted(delivery.text, raw: transcript.raw, app: recording.app)
            }
            let insertMs = (ContinuousClock.now - insertStarted).wholeMilliseconds
            if recording.inserts, let command = delivery.command { extensions.run(command, app: recording.app) }
            if recording.sends, recording.inserts, delivery.command == nil, !delivery.text.isEmpty, settings.insertIntoApp {
                await send(to: recording.app)
            }
            let record = await save(transcript, finalText: delivery.text.isEmpty ? transcript.cleaned.text : delivery.text, app: recording.app, released: released)
            report(record, model: transcript.model, insertMs: insertMs, trigger: recording.trigger)
            telemetry.recordDictation(app: recording.app, model: transcript.model, words: record.wordCount, totalMs: record.totalMs)
            logDebug(record, transcript, insertMs: insertMs)
            learnSpokenWords(in: transcript.raw)
            return .done
        } catch {
            Log.app.error("Transcription failed: \(error.localizedDescription, privacy: .private)")
            DebugLog.shared.write("dictation", ["outcome": "failed", "error": error.localizedDescription, "app": recording.app.name ?? ""])
            analytics.capture(.dictationFailed(stage: .transcription, errorCode: .transcriptionFailed))
            return .failed
        }
    }

    /// Presses Return for quick send, unless you switched apps meanwhile, so it can't trigger anything in the wrong window
    private func send(to app: HostApp) async {
        // The paste is still on its way to the app, and Return must land after it
        try? await Task.sleep(for: Self.sendDelay)
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == app.bundleID else {
            Log.app.notice("Quick send skipped: the front app changed")
            return
        }
        if let key = Self.sendKey { output.press(key) }
    }

    private static let sendDelay = Duration.milliseconds(120)
    private static let sendKey = try? KeyChord(parsing: "return")

    private func learnSpokenWords(in raw: String) {
        let candidates = SpokenCandidates.find(in: raw, isKnownWord: EditObserver.isKnownWord)
        guard !candidates.isEmpty else { return }
        Task { [vocabularyLearner] in await vocabularyLearner.consider(candidates) }
    }

    private func report(_ record: TranscriptRecord, model: String, insertMs: Int, trigger: DictationTrigger) {
        analytics.capture(.dictationCompleted(DictationMetrics(
            audioSeconds: record.audioSeconds,
            wordCount: record.wordCount,
            sttMs: record.sttMs,
            cleanupMs: record.cleanupMs,
            insertMs: insertMs,
            totalMs: record.totalMs,
            model: SpeechModel.analyticsLabel(for: model),
            selectedModel: SpeechModel.analyticsLabel(for: settings.speechModel),
            cleanupUsed: settings.cleanupEnabled,
            cleanupTimedOut: record.cleanupTimedOut,
            trigger: trigger,
            output: settings.insertIntoApp && Permissions.accessibilityGranted ? .paste : .clipboard
        )))
    }

    private func logDebug(_ record: TranscriptRecord, _ transcript: StreamedTranscript, insertMs: Int) {
        var fields: [String: Any] = [
            "outcome": "inserted",
            "app": record.appName ?? "",
            "model": record.model,
            "audio_s": record.audioSeconds,
            "words": record.wordCount,
            "ms": record.totalMs,
            "stt_ms": record.sttMs,
            "cleanup_ms": record.cleanupMs,
            "cleanup_timed_out": record.cleanupTimedOut,
            "insert_ms": insertMs,
            "segments": transcript.segmentCount,
        ]
        if settings.logIncludesText {
            fields["raw"] = record.rawText
            fields["text"] = record.finalText
        }
        DebugLog.shared.write("dictation", fields)
    }

    private func save(_ transcript: StreamedTranscript, finalText: String, app: HostApp, released: ContinuousClock.Instant) async -> TranscriptRecord {
        var record = TranscriptRecord(
            rawText: transcript.raw,
            finalText: finalText,
            audioSeconds: transcript.audioSeconds,
            sttMs: transcript.sttMs,
            totalMs: (ContinuousClock.now - released).wholeMilliseconds,
            model: transcript.model,
            appBundleID: app.bundleID,
            appName: app.name,
            fillerWordsRemoved: transcript.cleaned.fillerWordsRemoved,
            cleanupMs: transcript.cleaned.milliseconds,
            cleanupTimedOut: transcript.cleaned.timedOut
        )
        record.threadID = await thread(in: app)
        do {
            try await history.insert(record)
        } catch {
            Log.app.error("History save failed: \(error.localizedDescription, privacy: .private)")
            Analytics.report(.historySaveFailed, cause: error)
        }
        return record
    }

    /// The conversation the dictation went into, read from the front window's title
    private func thread(in app: HostApp) async -> UUID? {
        guard let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == app.bundleID else { return nil }
        let pid = front.processIdentifier, drafts = history.drafts
        return await Task.detached {
            try? drafts.thread(app: app.bundleID, window: FieldReader.windowTitle(pid: pid), appName: app.name)?.id
        }.value
    }
}
