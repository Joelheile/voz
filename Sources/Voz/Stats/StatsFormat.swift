import Foundation

enum StatsFormat {
    static func minutes(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        guard total >= 60 else { return "\(total) min" }
        return "\(total / 60) h \(total % 60) min"
    }

    static func days(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }
}
