import SwiftUI

struct ChangelogRelease: Equatable {
    let title: String
    var changes: [String] = []
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
    let releases: [ChangelogRelease]
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageBar(title: "What's new", back: back)
            CappedScrollView(maxHeight: 520) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(releases, id: \.title) { release in
                        PanelGroup(title: release.title) {
                            ForEach(release.changes, id: \.self) { change in
                                Text(LocalizedStringKey(change))
                                    .font(.ui(13))
                                    .lineSpacing(2)
                                    .foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
        }
    }
}
