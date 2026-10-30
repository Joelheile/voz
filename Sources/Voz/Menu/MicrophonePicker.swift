import SwiftUI

struct MicrophonePicker: View {
    @Binding var selection: String
    @State private var microphones = InputDevice.microphones()
    @State private var defaultName = InputDevice.defaultName()

    var body: some View {
        ModelPicker(
            title: "Microphone",
            selection: $selection,
            options: MicrophoneOptions.make(microphones, defaultName: defaultName, selection: selection)
        )
        .task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refresh() {
        let latest = InputDevice.microphones()
        if latest != microphones { microphones = latest }
        let latestDefault = InputDevice.defaultName()
        if latestDefault != defaultName { defaultName = latestDefault }
    }
}

enum MicrophoneOptions {
    static let systemDefault = ""

    static func make(_ microphones: [Microphone], defaultName: String?, selection: String) -> [ModelOption] {
        let systemDefault = ModelOption(id: systemDefault, name: "System default", detail: defaultName ?? "No microphone")
        let connected = microphones.map { ModelOption(id: $0.uid, name: $0.name, detail: $0.kind) }
        let selectionIsUnplugged = selection != Self.systemDefault && !microphones.contains { $0.uid == selection }
        let unplugged = selectionIsUnplugged ? [ModelOption(id: selection, name: "Unplugged microphone", detail: "Not connected, using default")] : []
        return [systemDefault] + connected + unplugged
    }
}
