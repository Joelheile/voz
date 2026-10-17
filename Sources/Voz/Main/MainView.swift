import SwiftUI
import VozCore

struct MainView: View {
    @ObservedObject var model: MainWindowModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var status: ModelStatus
    @ObservedObject var history: HistoryModel
    @ObservedObject var stats: StatsModel
    @ObservedObject var vocabulary: VocabularyModel
    let checkForUpdates: () -> Void

    static let windowSize = CGSize(width: 1100, height: 720)
    static let minimumSize = CGSize(width: 900, height: 600)

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model, settings: settings)
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).strokeBorder(Theme.hairline))
                .padding(.init(top: 12, leading: 0, bottom: 12, trailing: 12))
        }
        .background(Theme.canvas)
        .ignoresSafeArea()
        .tint(Theme.accent)
    }

    private var page: some View {
        ScrollView {
            Group {
                switch model.section {
                case .home: HomeView(history: history, stats: stats, settings: settings, openSettings: { model.section = .settings })
                case .insights: InsightsView(model: stats)
                case .dictionary: DictionaryView(model: vocabulary)
                case .settings: SettingsView(settings: settings, status: status, checkForUpdates: checkForUpdates)
                }
            }
            .frame(maxWidth: 960, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, 44)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
            .id(model.section)
            .transition(.opacity)
        }
        .scrollIndicators(.never)
        .animation(Theme.Motion.section, value: model.section)
    }
}
