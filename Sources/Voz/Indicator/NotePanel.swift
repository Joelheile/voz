import AppKit
import SwiftUI

@MainActor
@Observable
final class NoteModel {
    var title = ""
    var text = ""
}

/// One small note an extension opens, such as notes for a meeting. The user can move it anywhere.
@MainActor
final class NoteController {
    static let size = NSSize(width: 300, height: 150)
    private static let gapBelowMenuBar: CGFloat = 46
    private static let typingPause = Duration.milliseconds(400)

    private let model = NoteModel()
    private var panel: NotePanel?
    private var id: String?
    private var pendingSave: Task<Void, Never>?
    var onChange: (_ id: String, _ text: String) -> Void = { _, _ in }

    func show(_ note: ExtensionNote) {
        flush()
        id = note.id
        model.title = note.title
        model.text = note.text
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    func close(_ id: String? = nil) {
        guard let current = self.id, id == nil || id == current else { return }
        flush()
        self.id = nil
        panel?.orderOut(nil)
    }

    private func textChanged() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.typingPause)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    private func flush() {
        guard let pendingSave, let id else { return }
        pendingSave.cancel()
        self.pendingSave = nil
        onChange(id, model.text)
    }

    private func makePanel() -> NotePanel {
        let panel = NotePanel(contentRect: NSRect(origin: .zero, size: Self.size))
        panel.contentView = NSHostingView(rootView: NoteView(
            model: model,
            onEdit: { [weak self] in self?.textChanged() },
            onClose: { [weak self] in self?.close() }
        ))
        panel.onClose = { [weak self] in self?.close() }
        if !panel.setFrameUsingName(NotePanel.autosaveName), let screen = ScreenResolver.targetScreen() {
            panel.setFrameOrigin(NSPoint(
                x: screen.frame.midX - Self.size.width / 2,
                y: screen.visibleFrame.maxY - Self.gapBelowMenuBar - Self.size.height
            ))
        }
        panel.setFrameAutosaveName(NotePanel.autosaveName)
        return panel
    }
}

final class NotePanel: NSPanel {
    static let autosaveName = "VozNote"
    var onClose: () -> Void = {}

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onClose()
    }
}

struct NoteView: View {
    @Bindable var model: NoteModel
    let onEdit: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(model.title.isEmpty ? "Note" : model.title)
                    .font(.ui(13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                IconButton(icon: .x, help: "Close", action: onClose)
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .padding(.top, 4)
            ZStack(alignment: .topLeading) {
                if model.text.isEmpty {
                    Text("Write a note")
                        .font(.ui(13))
                        .foregroundStyle(Theme.inkTertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $model.text)
                    .font(.ui(13))
                    .foregroundStyle(Theme.ink)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .onChange(of: model.text) { onEdit() }
            }
            .padding(.horizontal, 9)
            .padding(.bottom, 10)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
    }
}
