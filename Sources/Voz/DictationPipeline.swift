import Foundation
import VozCore

@MainActor
final class DictationPipeline {
    private let engine: SpeechEngine
    private let cleaner: TextCleaner
    private let settings: AppSettings
    private let history: HistoryStore
    private let output: TextOutput
    private let editObserver: EditObserver
    private let analytics: Analytics
    private let extensions: ExtensionService

    init(
        engine: SpeechEngine,
        cleaner: TextCleaner,
        settings: AppSettings,
        history: HistoryStore,
        output: TextOutput,
        editObserver: EditObserver,
        analytics: Analytics,
        extensions: ExtensionService
    ) {
        self.engine = engine
        self.cleaner = cleaner
        self.settings = settings
        self.history = history
        self.output = output
        self.editObserver = editObserver
        self.analytics = analytics
        self.extensions = extensions
    }

    func collectLearnedWords() {
        editObserver.collect()
    }

    func makeStreaming(app: HostApp) -> StreamingDictation {
        let prompt = settings.cleanupPrompt
        return StreamingDictation(
            engine: engine,
            cleaner: cleaner,
            model: settings.speechModel,
            vocabulary: vocabularyWords(),
            prompt: Task { [extensions] in await extensions.cleanupPrompt(prompt, app: app) },
            cleanupEnabled: settings.cleanupEnabled
        )
    }

    func run(_ recording: Recording, streaming session: StreamingDictation, released: ContinuousClock.Instant) async -> Dictation.Outcome {
        extensions.recorded(recording.samples, app: recording.app)
        do {
            guard let transcript = try await session.finish(samples: recording.samples, released: released) else {
                Log.app.notice("Transcription was empty")
                analytics.capture(.dictationDiscarded(reason: .emptyTranscript))
                return .discarded
            }
            Log.app.notice("Transcribed \(transcript.audioSeconds, format: .fixed(precision: 1))s with \(transcript.model.rawValue): \(transcript.segmentCount) segments, \(transcript.cleanedInTime) cleaned in time, tail STT \(transcript.sttMs) ms, cleanup wait \(transcript.cleaned.milliseconds) ms")
            let delivery = await extensions.prepare(transcript.cleaned.text, raw: transcript.raw, app: recording.app)
            let insertStarted = ContinuousClock.now
            if !delivery.text.isEmpty {
                await output.deliver(delivery.text)
                if settings.insertIntoApp { editObserver.observe(inserted: delivery.text) }
            }
            let insertMs = (ContinuousClock.now - insertStarted).wholeMilliseconds
            if !delivery.text.isEmpty { extensions.inserted(delivery.text, raw: transcript.raw, app: recording.app) }
            if let command = delivery.command { extensions.run(command, text: delivery.text, app: recording.app) }
            let record = save(transcript, finalText: delivery.text.isEmpty ? transcript.cleaned.text : delivery.text, app: recording.app, released: released)
            report(record, model: transcript.model, insertMs: insertMs, trigger: recording.trigger)
            return .done
        } catch {
            Log.app.error("Transcription failed: \(error.localizedDescription, privacy: .private)")
            analytics.capture(.dictationFailed(stage: .transcription, errorCode: .transcriptionFailed))
            return .failed
        }
    }

    private func vocabularyWords() -> [String] {
        do {
            return try history.vocabulary.words()
        } catch {
            Log.app.error("Vocabulary read failed: \(error.localizedDescription, privacy: .private)")
            return []
        }
    }

    private func report(_ record: TranscriptRecord, model: SpeechModel, insertMs: Int, trigger: DictationTrigger) {
        analytics.capture(.dictationCompleted(DictationMetrics(
            audioSeconds: record.audioSeconds,
            wordCount: record.wordCount,
            sttMs: record.sttMs,
            cleanupMs: record.cleanupMs,
            insertMs: insertMs,
            totalMs: record.totalMs,
            model: model,
            selectedModel: settings.speechModel,
            cleanupUsed: settings.cleanupEnabled,
            cleanupTimedOut: record.cleanupTimedOut,
            trigger: trigger,
            output: settings.insertIntoApp && Permissions.accessibilityGranted ? .paste : .clipboard
        )))
    }

    private func save(_ transcript: StreamedTranscript, finalText: String, app: HostApp, released: ContinuousClock.Instant) -> TranscriptRecord {
        let record = TranscriptRecord(
            rawText: transcript.raw,
            finalText: finalText,
            audioSeconds: transcript.audioSeconds,
            sttMs: transcript.sttMs,
            totalMs: (ContinuousClock.now - released).wholeMilliseconds,
            model: transcript.model.rawValue,
            appBundleID: app.bundleID,
            appName: app.name,
            fillerWordsRemoved: transcript.cleaned.fillerWordsRemoved,
            cleanupMs: transcript.cleaned.milliseconds,
            cleanupTimedOut: transcript.cleaned.timedOut
        )
        do {
            try history.insert(record)
        } catch {
            Log.app.error("History save failed: \(error.localizedDescription, privacy: .private)")
        }
        return record
    }
}
