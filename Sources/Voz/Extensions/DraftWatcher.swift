import AppKit

/// Where a draft sits in its field, so later reads can tell what you did with it
struct DraftTrace: Equatable, Sendable {
    let output: String
    private let start: [Character]
    private let range: Range<Int>

    /// Nil when the field doesn't show the draft, as when the app ignored the paste
    init?(output: String, field: String) {
        guard !output.isEmpty, let found = field.range(of: output, options: .backwards) else { return nil }
        self.output = output
        start = Array(field)
        let lower = field.distance(from: field.startIndex, to: found.lowerBound)
        range = lower..<(lower + output.count)
    }

    /// The text where the draft was. Changes that touch it count as part of it; changes elsewhere in the field don't.
    func draft(in field: String) -> String {
        let now = Array(field)
        let shared = min(start.count, now.count)
        var prefix = 0
        while prefix < shared, start[prefix] == now[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < shared - prefix, start[start.count - 1 - suffix] == now[now.count - 1 - suffix] { suffix += 1 }
        guard prefix <= range.upperBound, start.count - suffix >= range.lowerBound else { return output }
        let lead = min(prefix, range.lowerBound)
        let tail = min(suffix, start.count - range.upperBound)
        return String(now[lead..<(now.count - tail)])
    }

    static func outcome(output: String, result: String) -> DraftOutcome {
        let result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty { return .removed }
        return result == output.trimmingCharacters(in: .whitespacesAndNewlines) ? .kept : .edited
    }
}

/// After an extension inserts a draft, reads the field every second until you send it, leave the conversation or two minutes pass
final class DraftWatcher: Sendable {
    static let interval = Duration.seconds(1)
    static let limit = Duration.seconds(120)
    private static let attempts = 4

    private let store: DraftStore

    init(store: DraftStore) {
        self.store = store
    }

    func watch(_ draft: DraftRecord, pid: pid_t) {
        let store = store
        Task.detached(priority: .utility) {
            let (result, outcome) = await Self.follow(output: draft.output, pid: pid)
            do {
                try store.finish(draft.id, result: result, outcome: outcome)
            } catch {
                Log.extensions.error("Could not save what happened to a draft: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// A field that empties while its window stays means a chat sent the message.
    private static func follow(output: String, pid: pid_t) async -> (String?, DraftOutcome) {
        guard let field = FieldReader.focusedTextElement(pid: pid) else { return (nil, .unknown) }
        var trace: DraftTrace?
        for _ in 0..<attempts {
            if let text = FieldReader.text(of: field), let found = DraftTrace(output: output, field: text) {
                trace = found
                break
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard let trace else { return (nil, .unknown) }
        let window = FieldReader.windowTitle(of: field)
        var last = output
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: interval)
            guard let text = FieldReader.text(of: field), FieldReader.windowTitle(of: field) == window else { break }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .removed : .sent)
            }
            last = trace.draft(in: text)
        }
        return (last, DraftTrace.outcome(output: output, result: last))
    }
}
