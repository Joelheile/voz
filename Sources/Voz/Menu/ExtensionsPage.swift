import SwiftUI
import VozCore

@MainActor
final class ExtensionsModel: ObservableObject {
    private static let search = URL(string: "https://registry.npmjs.org/-/v1/search?text=keywords:voz-package&size=100")!
    private let home = VozHome()

    @Published private(set) var packages: [PackageListing] = []
    @Published private(set) var installed: Set<String> = []
    @Published private(set) var working: String?
    @Published private(set) var message: String?

    func load() async {
        refreshInstalled()
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.search)
            packages = try PackageListing.decodeSearch(data)
            message = packages.isEmpty ? "No extensions published yet." : nil
        } catch {
            message = "Could not reach npm. Check your connection."
        }
    }

    func toggle(_ package: PackageListing) async {
        let name = package.name
        let remove = installed.contains(name)
        working = name
        do {
            try await Task.detached {
                if remove { try PackageCLI.remove(name) } else { try await PackageCLI.install("npm:\(name)") }
            }.value
            message = nil
        } catch {
            message = "\(error)"
        }
        working = nil
        refreshInstalled()
    }

    private func refreshInstalled() {
        let sources = (try? home.packageSources()) ?? []
        installed = Set(sources.compactMap { try? PackageSource(parsing: $0, relativeTo: home.root).name })
    }
}

struct ExtensionsPage: View {
    let back: () -> Void
    @StateObject private var model = ExtensionsModel()
    @State private var confirming: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageBar(title: "Extensions", back: back)
            Text("Extensions run code on your Mac and can read your transcripts. Install only ones you trust.")
                .font(.meta)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let message = model.message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.packages.isEmpty {
                CappedScrollView(maxHeight: 380) {
                    PanelGroup {
                        ForEach(model.packages) { package in
                            VStack(alignment: .leading, spacing: 0) {
                                PanelRow(title: package.name, detail: detail(for: package)) { control(for: package) }
                                if confirming == package.name { confirmation(for: package) }
                            }
                        }
                    }
                }
            }
        }
        .controlSize(.small)
        .task { await model.load() }
    }

    private func detail(for package: PackageListing) -> String {
        let downloads = "\(package.weeklyDownloads.formatted()) downloads a week"
        let meta = "\(package.publisher), v\(package.version), \(downloads)"
        return package.summary.map { "\($0)\n\(meta)" } ?? meta
    }

    @ViewBuilder
    private func control(for package: PackageListing) -> some View {
        if model.working == package.name {
            ProgressView()
        } else if model.installed.contains(package.name) {
            Button("Remove") { Task { await model.toggle(package) } }
                .buttonStyle(.pill(.quiet, height: 26))
                .disabled(model.working != nil)
        } else if confirming != package.name {
            Button("Install") { confirming = package.name }
                .buttonStyle(.pill(.accent, height: 26))
                .disabled(model.working != nil)
        }
    }

    private func confirmation(for package: PackageListing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(package.name) by \(package.publisher) can read your transcripts, your files and the network. Read its source before you install it.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if let page = package.page { Link("Read source", destination: page).font(.system(size: 12)) }
                Spacer(minLength: 0)
                Button("Cancel") { confirming = nil }
                    .buttonStyle(.pill(.quiet, height: 26))
                Button("Install") {
                    confirming = nil
                    Task { await model.toggle(package) }
                }
                .buttonStyle(.pill(.accent, height: 26))
            }
        }
        .padding(.bottom, 10)
    }
}
