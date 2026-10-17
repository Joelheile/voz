import SwiftUI
import VozCore

struct HomeView: View {
    @ObservedObject var history: HistoryModel
    @ObservedObject var stats: StatsModel
    @ObservedObject var settings: AppSettings
    let openSettings: () -> Void

    private var greeting: String {
        let first = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? "Welcome back" : "Welcome back, \(first)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.section) {
            Text(greeting)
                .font(.display(40, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(Theme.ink)
            HStack(alignment: .top, spacing: Theme.Spacing.block) {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    HeroCard(settings: settings, openSettings: openSettings)
                    HistoryList(model: history)
                }
                StatsCard(stats: stats.stats)
                    .frame(width: 252)
            }
        }
    }
}

private struct HeroCard: View {
    @ObservedObject var settings: AppSettings
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                SerifHeadline(lead: "Your voice,", accented: "typed.", size: 38, color: .white, accentColor: Theme.accentOnBlack)
                    .tracking(-0.6)
                Text(instruction)
                    .font(.system(size: 14.5))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Change shortcut", action: openSettings)
                    .buttonStyle(.pill(.light, height: 38))
                    .padding(.top, 8)
            }
            Spacer(minLength: 16)
            LevelBarsMark(heights: [0.35, 0.7, 1, 0.55, 0.8, 0.4], height: 84, barWidth: 9, spacing: 7, color: .white.opacity(0.92), accentIndex: 2)
                .padding(.trailing, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        .background(Theme.hero, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }

    private var instruction: String {
        let key = settings.hotkey.displayName
        return settings.holdToTalk
            ? "Hold \(key) in any app, speak, and let go. voz cleans it up on your Mac."
            : "Press \(key) in any app, speak, and press it again. voz cleans it up on your Mac."
    }
}

private struct StatsCard: View {
    let stats: UsageStats

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                StatNumber(value: stats.wordsTotal, unit: "total words", size: 38)
                StatNumber(value: Int((stats.averageWordsPerMinute ?? 0).rounded()), unit: "wpm", size: 38)
                StatNumber(value: stats.currentStreak, unit: stats.currentStreak == 1 ? "day streak" : "day streak", size: 38)
            }
            .padding(24)
            RowDivider()
            HStack {
                Text("Today")
                    .font(.meta)
                    .foregroundStyle(Theme.inkSecondary)
                Spacer()
                Text("\(stats.wordsToday.formatted()) words")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: Theme.Radius.card + 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card + 4, style: .continuous).strokeBorder(Theme.hairline))
    }
}
