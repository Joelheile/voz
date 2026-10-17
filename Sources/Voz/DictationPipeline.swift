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

    init(
        engine: SpeechEngine,
        cleaner: TextCleaner,
        settings: AppSettings,
        history: HistoryStore,
        output: TextOutput,
        editObserver: EditObserver,
        analytics: Analytics
    ) {
        self.engine = engine
        self.cleaner = cleaner
        self.settings = settings
        self.history = history
        self.output = output
        self.editObserver = editObserver
        self.analytics = analytics
    }

    func collectLearnedWords() {
        editObserver.collect()
    }

    func makeStreaming() -> StreamingDictation {
        StreamingDictation(
            engine: engine,
            cleaner: cleaner,
            mode: settings.languageMode,
            vocabulary: vocabularyWords(),
            cleanupEnabled: settings.cleanupEnabled
        )
    }

    func run(_ recording: LastRecording, streaming: StreamingDictation?, released: ContinuousClock.Instant) async -> Dictation.Outcome {
        let session = streaming ?? makeStreaming()
        do {
            guard let transcript = try await session.finish(samples: recording.samples, released: released) else {
                Log.app.notice("Transcription was empty")
                analytics.capture(.dictationDiscarded(reason: .emptyTranscript))
                return .discarded
            }
            Log.app.notice("Transcribed \(transcript.audioSeconds, format: .fixed(precision: 1))s with \(transcript.model): \(transcript.segmentCount) segments, \(transcript.cleanedInTime) cleaned in time, tail STT \(transcript.sttMs) ms, cleanup wait \(transcript.cleaned.milliseconds) ms")
            let insertStarted = ContinuousClock.now
            await output.deliver(transcript.cleaned.text)
            let insertMs = (ContinuousClock.now - insertStarted).wholeMilliseconds
            if settings.insertIntoApp { editObserver.observe(inserted: transcript.cleaned.text) }
            let record = save(transcript, app: recording.app, released: released)
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

    private func report(_ record: TranscriptRecord, model modelName: String, insertMs: Int, trigger: DictationTrigger) {
        guard let model = SpeechModel(rawValue: modelName) else {
            Log.app.error("Unknown speech model, dictation event skipped: \(modelName)")
            return
        }
        analytics.capture(.dictationCompleted(DictationMetrics(
            audioSeconds: record.audioSeconds,
            wordCount: record.wordCount,
            sttMs: record.sttMs,
            cleanupMs: record.cleanupMs,
            insertMs: insertMs,
            totalMs: record.totalMs,
            model: model,
            languageMode: settings.languageMode,
            cleanupUsed: settings.cleanupEnabled,
            cleanupTimedOut: record.cleanupTimedOut,
            trigger: trigger,
            output: settings.insertIntoApp && Permissions.accessibilityGranted ? .paste : .clipboard
        )))
    }

    private func save(_ transcript: StreamedTranscript, app: FrontApp, released: ContinuousClock.Instant) -> TranscriptRecord {
        let record = TranscriptRecord(
            rawText: transcript.raw,
            finalText: transcript.cleaned.text,
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
        do {
            try history.insert(record)
        } catch {
            Log.app.error("History save failed: \(error.localizedDescription, privacy: .private)")
        }
        return record
    }
}
