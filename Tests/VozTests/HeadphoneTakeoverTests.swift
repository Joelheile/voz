import Testing
@testable import Voz

private let start = ContinuousClock.now

@Test func headphonesThatConnectAndTakeTheMicGiveItBack() {
    var takeover = HeadphoneTakeover(inputs: ["built-in"], current: "built-in")
    takeover.inputsChanged(to: ["built-in", "headset"], at: start)
    #expect(takeover.defaultChanged(to: "headset", isBluetooth: true, at: start + .seconds(1)) == "built-in")
}

@Test func takeoverAnnouncedBeforeTheDeviceListStillGivesTheMicBack() {
    var takeover = HeadphoneTakeover(inputs: ["built-in"], current: "built-in")
    #expect(takeover.defaultChanged(to: "headset", isBluetooth: true, at: start) == "built-in")
}

@Test func headphonesPickedLaterStayPicked() {
    var takeover = HeadphoneTakeover(inputs: ["built-in"], current: "built-in")
    takeover.inputsChanged(to: ["built-in", "headset"], at: start)
    #expect(takeover.defaultChanged(to: "headset", isBluetooth: true, at: start + .seconds(30)) == nil)
    #expect(takeover.defaultChanged(to: "built-in", isBluetooth: false, at: start + .seconds(40)) == nil)
}

@Test func wiredMicsThatConnectKeepTheMic() {
    var takeover = HeadphoneTakeover(inputs: ["built-in"], current: "built-in")
    takeover.inputsChanged(to: ["built-in", "usb"], at: start)
    #expect(takeover.defaultChanged(to: "usb", isBluetooth: false, at: start) == nil)
}

@Test func noMicToGoBackToMeansHeadphonesKeepIt() {
    var takeover = HeadphoneTakeover(inputs: ["usb"], current: "usb")
    takeover.inputsChanged(to: ["headset"], at: start)
    #expect(takeover.defaultChanged(to: "headset", isBluetooth: true, at: start) == nil)
}
