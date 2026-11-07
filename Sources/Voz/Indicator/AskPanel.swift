import AppKit
import LucideSwift
import SwiftUI

@MainActor
@Observable
final class AskModel {
    var title = ""
    var message: String?
    var icon: LucideIconName?
    var fields: [AskField] = []
    var buttons: [String] = []
    var texts: [String: String] = [:]
    var dates: [String: Date] = [:]

    func load(_ params: AskParams) {
        title = params.title
        message = params.message
        icon = params.icon.flatMap(ExtensionsModel.lucideIcon(named:))
        fields = params.fields
        buttons = params.buttons
        texts = [:]
        dates = [:]
        for field in params.fields {
            switch (field.type, field.value) {
            case (.date, .number(let milliseconds)): dates[field.id] = Date(timeIntervalSince1970: milliseconds / 1000)
            case (.date, _): dates[field.id] = Date()
            case (_, .string(let text)): texts[field.id] = text
            default: texts[field.id] = ""
            }
        }
    }

    var values: [String: JSONValue] {
        var values = texts.mapValues(JSONValue.string)
        for (id, date) in dates { values[id] = .number((date.timeIntervalSince1970 * 1000).rounded()) }
        return values
    }
}

/// A card under the notch where an extension asks the user to confirm or edit something. It stays until the user answers.
@MainActor
final class AskController {
    static let width: CGFloat = 340
    private static let gapBelowMenuBar: CGFloat = 46

    private let model = AskModel()
    private var panel: NotePanel?
    private var waiting: CheckedContinuation<AskAnswer?, Never>?

    var isOpen: Bool { waiting != nil }

    /// A new question replaces the open one, which answers `nil`
    func ask(_ params: AskParams) async -> AskAnswer? {
        finish(nil)
        model.load(params)
        show()
        return await withCheckedContinuation { waiting = $0 }
    }

    func close() {
        finish(nil)
    }

    private func finish(_ answer: AskAnswer?) {
        panel?.orderOut(nil)
        waiting?.resume(returning: answer)
        waiting = nil
    }

    private func show() {
        guard let screen = ScreenResolver.targetScreen() else { return finish(nil) }
        let panel = panel ?? makePanel()
        self.panel = panel
        let hosting = NSHostingController(rootView: view)
        let size = hosting.sizeThatFits(in: NSSize(width: Self.width, height: .infinity))
        hosting.view.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting.view
        panel.setFrame(NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.visibleFrame.maxY - Self.gapBelowMenuBar - size.height,
            width: size.width,
            height: size.height
        ), display: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private var view: AskView {
        AskView(
            model: model,
            onAnswer: { [weak self] button in
                guard let self else { return }
                finish(AskAnswer(button: button, values: model.values))
            },
            onClose: { [weak self] in self?.close() }
        )
    }

    private func makePanel() -> NotePanel {
        let panel = NotePanel(contentRect: .zero)
        panel.onClose = { [weak self] in self?.close() }
        return panel
    }
}

struct AskView: View {
    @Bindable var model: AskModel
    let onAnswer: (String) -> Void
    let onClose: () -> Void
    @FocusState private var focused: String?

    /// A card that asks for one text needs no label column: the label becomes the placeholder, and you can type right away
    private var isSingleText: Bool { model.fields.count == 1 && model.fields[0].type == .text }

    var body: some View {
        Group {
            if model.fields.isEmpty, model.buttons.count > 1 { prompt } else { form }
        }
        .frame(width: AskController.width)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .onAppear { if isSingleText { focused = model.fields[0].id } }
    }

    /// A question with only buttons fits one row, like a notification, and its first button dismisses it
    private var prompt: some View {
        HStack(spacing: 10) {
            if let icon = model.icon {
                Icon(icon, size: 16)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
                    .background(Theme.selected, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(model.title)
                    .font(.ui(13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                if let message = model.message {
                    Text(message)
                        .font(.ui(12))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            buttons(.small)
        }
        .padding(.leading, model.icon == nil ? 14 : 10)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                Text(model.title)
                    .font(.ui(14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Spacer(minLength: 8)
                IconButton(icon: .x, help: "Close", action: onClose)
                    .padding(.trailing, -4)
            }
            if !model.fields.isEmpty {
                PanelGroup {
                    ForEach(model.fields, id: \.id) { field in
                        HStack(spacing: 10) {
                            if !isSingleText {
                                Text(field.label)
                                    .font(.ui(12))
                                    .foregroundStyle(Theme.inkTertiary)
                                    .frame(width: 64, alignment: .leading)
                            }
                            control(for: field)
                        }
                        .frame(minHeight: 34)
                    }
                }
            }
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                buttons(.regular)
            }
        }
        .padding(12)
    }

    private func buttons(_ size: PillSize) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(model.buttons.enumerated()), id: \.offset) { index, button in
                if index == model.buttons.count - 1 {
                    Button(button) { onAnswer(button) }
                        .buttonStyle(.pill(.accent, size))
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(button) { onAnswer(button) }
                        .buttonStyle(.pill(.quiet, size))
                }
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func control(for field: AskField) -> some View {
        switch field.type {
        case .text:
            TextField("", text: text(field.id), prompt: isSingleText ? Text(field.label).foregroundStyle(Theme.inkTertiary) : nil)
                .textFieldStyle(.plain)
                .focused($focused, equals: field.id)
                .font(.ui(13))
                .foregroundStyle(Theme.ink)
        case .date:
            DatePicker("", selection: date(field.id), displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.field)
                .font(.ui(13))
            Spacer(minLength: 0)
        case .choice:
            Picker("", selection: text(field.id)) {
                ForEach(field.options ?? [], id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            Spacer(minLength: 0)
        }
    }

    private func text(_ id: String) -> Binding<String> {
        Binding(get: { model.texts[id] ?? "" }, set: { model.texts[id] = $0 })
    }

    private func date(_ id: String) -> Binding<Date> {
        Binding(get: { model.dates[id] ?? Date() }, set: { model.dates[id] = $0 })
    }
}
