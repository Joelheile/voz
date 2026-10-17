import Combine

enum MainSection: String, CaseIterable, Identifiable {
    case home
    case insights
    case dictionary
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .insights: "Insights"
        case .dictionary: "Dictionary"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .insights: "chart.bar"
        case .dictionary: "text.book.closed"
        case .settings: "gearshape"
        }
    }
}

@MainActor
final class MainWindowModel: ObservableObject {
    @Published var section = MainSection.home
}
