import Testing
@testable import Voz

private let headset = Microphone(uid: "headset-uid", name: "AirPods Pro", kind: "Bluetooth")
private let builtIn = Microphone(uid: "built-in-uid", name: "MacBook Pro Microphone", kind: "Built in")

@Test func systemDefaultComesFirstAndNamesTheMicItUses() {
    let options = MicrophoneOptions.make([builtIn, headset], defaultName: "MacBook Pro Microphone", selection: MicrophoneOptions.systemDefault)
    #expect(options.map(\.id) == [MicrophoneOptions.systemDefault, "built-in-uid", "headset-uid"])
    #expect(options[0].name == "System default")
    #expect(options[0].detail == "MacBook Pro Microphone")
}

@Test func unpluggedMicStaysSelectedAndSaysItFallsBack() {
    let options = MicrophoneOptions.make([builtIn], defaultName: "MacBook Pro Microphone", selection: "headset-uid")
    #expect(options.map(\.id) == [MicrophoneOptions.systemDefault, "built-in-uid", "headset-uid"])
    #expect(options.last?.detail == "Not connected, using default")
}

@Test func connectedSelectionIsListedOnce() {
    let options = MicrophoneOptions.make([builtIn, headset], defaultName: nil, selection: "headset-uid")
    #expect(options.filter { $0.id == "headset-uid" }.count == 1)
    #expect(options[0].detail == "No microphone")
}
