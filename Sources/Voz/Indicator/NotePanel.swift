import AppKit
import SwiftUI

@MainActor
@Observable
final class NoteModel {
    var title = ""
    var text = ""
    var hovering = false
    var focused = false
    var live: LiveStatus?
    /// The part of the window behind the notch, so the note looks attached to it
    var tucked: CGFloat = 0

    /// The note shows two lines under the notch, and opens up while the user points at it or types
    var expanded: Bool { hovering || focused }
    /// While a live transcription runs, the note offers to copy what it heard
    var listening: Bool { live?.running == true }
}

enum NoteMotion {
    /// Strong ease-out, shared by the window frame and its content so both land together
    static let curve = (0.23, 1.0, 0.32, 1.0)
    static let duration = 0.22
    static let resize = Animation.timingCurve(curve.0, curve.1, curve.2, curve.3, duration: duration)
    /// Passing over the notch on the way to the menu bar doesn't open the note
    static let openDelay = Duration.milliseconds(120)
    static let closeDelay = Duration.milliseconds(300)
}

/// One note an extension opens, such as notes for a meeting. It sits under the notch.
@MainActor
final class NoteController {
    static let width: CGFloat = 360
    static let expandedHeight: CGFloat = 240
    /// Two lines of text and the padding around them
    static let compactHeight: CGFloat = 64
    private static let gapBelowMenuBar: CGFloat = 8
    /// A little narrower than the notch, so the note hangs from it like a tab
    private static let notchInset: CGFloat = 16
    private static let typingPause = Duration.milliseconds(400)

    private let model = NoteModel()
    private var panel: NotePanel?
    private var id: String?
    private var pendingSave: Task<Void, Never>?
    private var pendingHover: Task<Void, Never>?

    init(live: LiveStatus? = nil) {
        model.live = live
    }
    var onChange: (_ id: String, _ text: String) -> Void = { _, _ in }

    /// `quietly` leaves the keyboard with the app the user is in, such as a call. Showing the open note again focuses it.
    func show(_ note: ExtensionNote, quietly: Bool = false) {
        let focus = !quietly || (panel?.isVisible == true && id == note.id)
        flush()
        id = note.id
        model.title = note.title
        model.text = note.text
        let panel = panel ?? makePanel()
        self.panel = panel
        place(animated: false)
        if focus {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func close(_ id: String? = nil) {
        guard let current = self.id, id == nil || id == current else { return }
        flush()
        self.id = nil
        panel?.orderOut(nil)
    }

    /// During a meeting the note copies everything said so far, since the user already sees their own notes
    private func copy() {
        let text = model.listening ? model.live?.transcript ?? "" : model.text
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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

    private func setHovering(_ hovering: Bool) {
        pendingHover?.cancel()
        guard model.hovering != hovering else { return }
        pendingHover = Task { [weak self] in
            try? await Task.sleep(for: hovering ? NoteMotion.openDelay : NoteMotion.closeDelay)
            guard !Task.isCancelled, let self else { return }
            self.model.hovering = hovering
            self.place(animated: true)
        }
    }

    private func setFocused(_ focused: Bool) {
        guard model.focused != focused else { return }
        model.focused = focused
        place(animated: true)
    }

    /// Hangs from the bottom of the notch, so the note grows and shrinks downward
    private func place(animated: Bool) {
        guard let panel, let screen = ScreenResolver.targetScreen() else { return }
        let layout = IndicatorLayout.make(screen: ScreenResolver.metrics(for: screen))
        let underNotch = layout.style == .notch
        model.tucked = underNotch ? Theme.Radius.panel : 0
        panel.appearance = underNotch ? NSAppearance(named: .darkAqua) : nil
        let top = underNotch ? layout.panelFrame.minY + model.tucked : screen.visibleFrame.maxY - Self.gapBelowMenuBar
        let width = underNotch ? layout.panelFrame.width - 2 * (IndicatorLayout.notchFlare + Self.notchInset) : Self.width
        let height = (model.expanded ? Self.expandedHeight : Self.compactHeight) + model.tucked
        let frame = NSRect(x: screen.frame.midX - width / 2, y: top - height, width: width, height: height)
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return panel.setFrame(frame, display: true)
        }
        let curve = NoteMotion.curve
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NoteMotion.duration
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: Float(curve.0), Float(curve.1), Float(curve.2), Float(curve.3)
            )
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func makePanel() -> NotePanel {
        let panel = NotePanel(contentRect: NSRect(origin: .zero, size: NSSize(width: Self.width, height: Self.compactHeight)))
        panel.contentView = NSHostingView(rootView: NoteView(
            model: model,
            onEdit: { [weak self] in self?.textChanged() },
            onCopy: { [weak self] in self?.copy() },
            onHover: { [weak self] in self?.setHovering($0) },
            onClose: { [weak self] in self?.close() }
        ))
        panel.onClose = { [weak self] in self?.close() }
        panel.onFocus = { [weak self] in self?.setFocused($0) }
        return panel
    }
}

final class NotePanel: NSPanel {
    var onClose: () -> Void = {}
    var onFocus: (Bool) -> Void = { _ in }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        // The window shadow outlines the glass with a dark rim, so the glass draws its own edge
        hasShadow = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // Above the menu bar, so the top tucks behind the notch instead of showing a strip of menu bar
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Notes stay private when the user shares their screen in a call
        sharingType = .none
    }

    override var canBecomeKey: Bool { true }

    /// AppKit keeps windows out of the menu bar, which would push the top edge out from behind the notch
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override func becomeKey() {
        super.becomeKey()
        onFocus(true)
    }

    override func resignKey() {
        super.resignKey()
        onFocus(false)
    }

    override func cancelOperation(_ sender: Any?) {
        onClose()
    }
}

struct NoteView: View {
    @Bindable var model: NoteModel
    let onEdit: () -> Void
    var onCopy: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.live?.stalled == true {
                stallWarning
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .transition(.noteContent)
            }
            if model.expanded {
                if !model.listening {
                    header.transition(.noteContent)
                }
                editor
                    .padding(.horizontal, 16)
                    .padding(.top, model.listening ? 12 : 4)
                    .mask {
                        VStack(spacing: 0) {
                            Color.black
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: NoteStyle.fade)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if model.listening {
                            IconButton(icon: .copy, help: "Copy the transcript", size: 13, strokeWidth: 1, action: onCopy)
                                .disabled(model.live?.transcript.isEmpty != false)
                                .padding(.top, 4)
                                .padding(.trailing, 6)
                        }
                    }
                    .transition(.noteContent)
            } else {
                Group {
                    if model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(model.title.isEmpty ? "Write a note" : model.title)
                            .font(.system(size: NoteStyle.size))
                            .foregroundStyle(Theme.inkTertiary)
                    } else {
                        NoteSnippet(text: model.text)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .transition(.noteContent)
            }
        }
        .padding(.top, model.tucked)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: shape)
        .contentShape(shape)
        .onHover(perform: onHover)
        .animation(reduceMotion ? Theme.Motion.section : NoteMotion.resize, value: model.expanded)
    }

    /// Square on top where the note hangs from the notch, so the two read as one shape
    private var shape: UnevenRoundedRectangle {
        let top = model.tucked > 0 ? 0 : Theme.Radius.panel
        return UnevenRoundedRectangle(
            topLeadingRadius: top, bottomLeadingRadius: Theme.Radius.panel,
            bottomTrailingRadius: Theme.Radius.panel, topTrailingRadius: top, style: .continuous
        )
    }

    private var stallWarning: some View {
        Label {
            Text("Can't hear the meeting. Reconnecting")
        } icon: {
            Icon(.triangleAlert, size: 13, strokeWidth: 2)
        }
        .font(.ui(13, weight: .medium))
        .foregroundStyle(Theme.failure)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(model.title.isEmpty ? "Note" : model.title)
                .font(.ui(13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            IconButton(icon: .copy, help: "Copy", size: 13, strokeWidth: 1, action: onCopy)
            IconButton(icon: .x, help: "Close", size: 13, strokeWidth: 1, action: onClose)
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.top, 6)
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if model.text.isEmpty {
                Text("Start writing…")
                    .font(.system(size: NoteStyle.size))
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.top, 2)
                    .allowsHitTesting(false)
            }
            NoteEditor(text: $model.text, onEdit: onEdit)
        }
    }
}

private struct NoteContentEffect: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        content.blur(radius: hidden ? 4 : 0).opacity(hidden ? 0 : 1)
    }
}

extension AnyTransition {
    /// Content crossfades with a little blur, so the swap reads as one surface changing
    static var noteContent: AnyTransition {
        .modifier(active: NoteContentEffect(hidden: true), identity: NoteContentEffect(hidden: false))
    }
}
