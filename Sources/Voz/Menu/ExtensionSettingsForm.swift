import SwiftUI
import VozCore

struct ExtensionSettingsForm: View {
    let fields: [SettingField]
    let config: [String: SettingValue]
    let save: (SettingValue, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(fields, id: \.key) { field in
                PanelRow(title: field.title, detail: field.description) {
                    SettingControl(field: field, value: field.value(in: config)) { save($0, field.key) }
                }
            }
        }
        .padding(.leading, 12)
        .padding(.bottom, 6)
    }
}

private struct SettingControl: View {
    private static let fieldWidth: CGFloat = 140

    let field: SettingField
    let value: SettingValue
    let save: (SettingValue) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        switch (field.type, field.options) {
        case (.boolean, _):
            Toggle(field.title, isOn: Binding { value == .boolean(true) } set: { save(.boolean($0)) })
                .labelsHidden()
        case (.string, let options?):
            Picker(field.title, selection: Binding { value.text } set: { save(.string($0)) }) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        default:
            entry
        }
    }

    private var entry: some View {
        Group {
            if field.secret == true {
                SecureField(field.title, text: $text)
            } else {
                TextField(field.title, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(.ui(12.5))
        .foregroundStyle(Theme.ink)
        .focused($focused)
        .onSubmit(commit)
        .onChange(of: focused) { if !focused { commit() } }
        .onAppear { text = value.text }
        .padding(.horizontal, 10)
        .frame(width: Self.fieldWidth, height: 26)
        .background(Theme.canvas, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
    }

    private func commit() {
        let entered = field.type == .number ? Double(text).map(SettingValue.number) : .string(text)
        guard let entered else { return text = value.text }
        if entered != value { save(entered) }
    }
}
