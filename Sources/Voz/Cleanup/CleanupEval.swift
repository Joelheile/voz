import Foundation

struct CleanupEvalCase: Decodable {
    let id: Int
    let category: String
    let input: String
    let expected: String?
    let vocabulary: [String]?
}

@MainActor
enum CleanupEval {
    static func run(path: String, repeats: Int, budget: Duration) async -> Int32 {
        let cases: [CleanupEvalCase]
        do {
            cases = try JSONDecoder().decode([CleanupEvalCase].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        } catch {
            Headless.printError("eval fixture unreadable: \(error)")
            return 66
        }
        let cleaner = TextCleaner(budget: budget)
        cleaner.prewarm(prompt: CleanupPrompt.standard, vocabulary: [])
        try? await Task.sleep(for: .seconds(1))
        _ = await cleaner.clean("um so can you uh send me the report by friday", prompt: CleanupPrompt.standard, vocabulary: [])

        var allLatencies: [Int] = []
        var scored = 0
        var passed = 0
        var rejections = 0
        var timeouts = 0
        for evalCase in cases {
            var latencies: [Int] = []
            var last: CleanedText?
            for _ in 0..<repeats {
                let result = await cleaner.clean(evalCase.input, prompt: CleanupPrompt.standard, vocabulary: evalCase.vocabulary ?? [])
                latencies.append(result.milliseconds)
                last = result
                try? await Task.sleep(for: .seconds(1.5))
                if result.rejection != nil { rejections += 1 }
                if result.timedOut { timeouts += 1 }
            }
            allLatencies += latencies
            guard let last else { continue }
            let status: String
            if let expected = evalCase.expected {
                scored += 1
                let matches = normalized(last.text) == normalized(expected)
                if matches { passed += 1 }
                status = matches ? "pass" : "FAIL"
            } else {
                status = "n/a "
            }
            let flags = [last.rejection.map { "rejected:\($0.rawValue)" }, last.timedOut ? "timeout" : nil].compactMap { $0 }.joined(separator: " ")
            print("\(status) #\(evalCase.id) \(evalCase.category) p50 \(percentile(latencies, 0.5)) ms p95 \(percentile(latencies, 0.95)) ms \(flags)")
            if status == "FAIL", let expected = evalCase.expected {
                print("  input:    \(evalCase.input)\n  expected: \(expected)\n  got:      \(last.text)")
            }
        }
        print("match ignoring commas \(passed)/\(scored), guard rejections \(rejections), timeouts \(timeouts), p50 \(percentile(allLatencies, 0.5)) ms, p95 \(percentile(allLatencies, 0.95)) ms")
        return 0
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: ",", with: "")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!? "))
    }

    private static func percentile(_ values: [Int], _ fraction: Double) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = Int((fraction * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }
}
