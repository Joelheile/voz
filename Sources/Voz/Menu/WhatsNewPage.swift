import SwiftUI

struct ChangelogRelease: Equatable {
    let title: String
    var changes: [String] = []

    var name: String {
        title.split(separator: " (", maxSplits: 1).first.map(String.init) ?? title
    }

    var date: String? {
        guard title.hasSuffix(")"), let open = title.range(of: " (") else { return nil }
        return String(title[open.upperBound..<title.index(before: title.endIndex)])
    }
}

enum Changelog {
    static let bundled: [ChangelogRelease] = {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text)
    }()

    static func parse(_ markdown: String) -> [ChangelogRelease] {
        var releases: [ChangelogRelease] = []
        for line in markdown.split(separator: "\n") {
            if line.hasPrefix("## ") {
                releases.append(ChangelogRelease(title: String(line.dropFirst(3))))
            } else if line.hasPrefix("- "), !releases.isEmpty {
                releases[releases.count - 1].changes.append(String(line.dropFirst(2)))
            }
        }
        return releases
    }
}

struct WhatsNewPage: View {
    @ObservedObject var settings: AppSettings
    let releases: [ChangelogRelease]
    let checkForUpdates: () -> Void
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageBar(title: "What's new", back: back)
            CappedScrollView(maxHeight: 520) {
                VStack(alignment: .leading, spacing: 16) {
                    PanelGroup {
                        PanelRow(title: "Voz \(Self.version)", detail: "Updates install on their own") {
                            Button("Check now", action: checkForUpdates)
                                .buttonStyle(.pill(.quiet, .small))
                        }
                        PanelRow(title: "Beta updates") {
                            Toggle("Beta updates", isOn: $settings.receiveBetaUpdates).labelsHidden()
                        }
                    }
                    ForEach(releases, id: \.title) { release in
                        ReleaseNotes(release: release)
                    }
                }
            }
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

private struct ReleaseNotes: View {
    let release: ChangelogRelease

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(release.name).font(.ui(13, weight: .semibold)).foregroundStyle(Theme.ink)
                if let date = release.date {
                    Text(date).font(.meta).foregroundStyle(Theme.inkTertiary)
                }
            }
            ForEach(release.changes, id: \.self) { change in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(Theme.inkTertiary)
                    Text(LocalizedStringKey(change))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.ui(13))
                .lineSpacing(2)
            }
        }
    }
}
