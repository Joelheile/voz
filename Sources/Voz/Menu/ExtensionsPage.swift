import SwiftUI
import VozCore

struct NpmPackage: Decodable, Identifiable {
    let name: String
    let description: String?
    var id: String { name }
}

private struct NpmSearchResult: Decodable {
    struct Object: Decodable { let package: NpmPackage }
    let objects: [Object]
}

@MainActor
final class ExtensionsModel: ObservableObject {
    private static let search = URL(string: "https://registry.npmjs.org/-/v1/search?text=keywords:voz-package&size=100")!
    private let home = VozHome()

    @Published private(set) var packages: [NpmPackage] = []
    @Published private(set) var installed: Set<String> = []
    @Published private(set) var working: String?
    @Published private(set) var message: String?

    func load() async {
        refreshInstalled()
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.search)
            packages = try JSONDecoder().decode(NpmSearchResult.self, from: data).objects.map(\.package)
            message = packages.isEmpty ? "No extensions published yet." : nil
        } catch {
            message = "Could not reach npm. Check your connection."
        }
    }

    func toggle(_ package: NpmPackage) async {
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
                            PanelRow(title: package.name, detail: package.description) { control(for: package) }
                        }
                    }
                }
            }
        }
        .controlSize(.small)
        .task { await model.load() }
    }

    @ViewBuilder
    private func control(for package: NpmPackage) -> some View {
        if model.working == package.name {
            ProgressView()
        } else {
            let installed = model.installed.contains(package.name)
            Button(installed ? "Remove" : "Install") { Task { await model.toggle(package) } }
                .buttonStyle(.pill(installed ? .quiet : .accent, height: 26))
                .disabled(model.working != nil)
        }
    }
}
