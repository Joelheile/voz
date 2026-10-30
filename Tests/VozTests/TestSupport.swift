import AVFoundation
import AppKit
import Synchronization
@testable import Voz

func makeRecord(_ text: String, at seconds: Double = 0) -> TranscriptRecord {
    TranscriptRecord(
        createdAt: Date(timeIntervalSince1970: seconds),
        rawText: text,
        audioSeconds: 2,
        sttMs: 100,
        totalMs: 200,
        model: "parakeet-tdt-v3",
        appBundleID: "com.apple.Notes",
        appName: "Notes"
    )
}

func makeTemporaryStorePath() -> String {
    NSTemporaryDirectory() + "voz-test-\(UUID().uuidString).sqlite"
}

func removeFile(atPath path: String) {
    try? FileManager.default.removeItem(atPath: path)
}

let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

func utcStats(_ store: HistoryStore, at seconds: Double) throws -> UsageStats {
    try store.stats(now: Date(timeIntervalSince1970: seconds), calendar: utcCalendar)
}

let installedBun = ["BUN_PATH", "HOME"]
    .compactMap { ProcessInfo.processInfo.environment[$0] }
    .map { $0.hasSuffix("bun") ? URL(fileURLWithPath: $0) : URL(fileURLWithPath: $0).appendingPathComponent(".bun/bin/bun") }
    .first { FileManager.default.isExecutableFile(atPath: $0.path) }

let hostScript = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources/Extensions/host.ts")

let extensionResources = hostScript.deletingLastPathComponent()

func temporaryHome() -> VozHome {
    VozHome(root: FileManager.default.temporaryDirectory.appendingPathComponent("voz-home-\(UUID().uuidString)"))
}

func fileURL(_ path: String) -> URL {
    URL(fileURLWithPath: path)
}

func writeFile(_ contents: String, named name: String, in directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(contents.utf8).write(to: directory.appendingPathComponent(name))
}

func fileContents(_ url: URL) -> String? {
    try? String(contentsOf: url, encoding: .utf8)
}

func posixPermissions(_ url: URL) -> Int? {
    try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
}

final class RecordedActions: @unchecked Sendable {
    private let lock = NSLock()
    private var actions: [HostAction] = []

    func append(_ action: HostAction) { lock.withLock { actions.append(action) } }
    var all: [HostAction] { lock.withLock { actions } }
}

final class RecordedLogs: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) { lock.withLock { lines.append(line) } }

    func waitFor(_ matches: (String) -> Bool) async throws -> Bool {
        for _ in 0..<40 {
            if lock.withLock({ lines.contains(where: matches) }) { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}

func hostApiVersion() -> String? {
    guard let host = fileContents(hostScript), let start = host.range(of: "const apiVersion = ")?.upperBound else { return nil }
    return String(host[start...].prefix(while: \.isNumber))
}

private struct HostLaunch: Encodable {
    let home: String
    let settings: String
    let extensionsDirectory: String
    let packages: [String] = []
}

func hostOutlivesClosedInput(home: VozHome) async throws -> Bool {
    let arguments = HostLaunch(home: home.root.path, settings: home.settings.path, extensionsDirectory: home.extensions.path)
    let process = Process()
    process.executableURL = installedBun
    process.arguments = ["--no-install", hostScript.path, String(decoding: try JSONEncoder().encode(arguments), as: UTF8.self)]
    let input = Pipe()
    process.standardInput = input
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    defer { if process.isRunning { process.terminate() } }
    try input.fileHandleForWriting.close()
    for _ in 0..<30 where process.isRunning { try await Task.sleep(for: .milliseconds(100)) }
    return process.isRunning
}

func processIsGone(_ pid: Int32) async throws -> Bool {
    for _ in 0..<30 where kill(pid, 0) == 0 { try await Task.sleep(for: .milliseconds(100)) }
    return kill(pid, 0) != 0
}

func localSource(_ path: String) -> PackageSource {
    .local(URL(fileURLWithPath: path))
}

func makeVersionPingQueue() -> () throws -> VersionPingQueue {
    let suite = UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    return { try VersionPingQueue(defaults: defaults) }
}

func recordLaunches(_ versions: [String]) -> [LaunchVersion] {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    return versions.map { LaunchVersion.record($0, in: defaults) }
}

func makePingID() -> (UUID, String) {
    let id = UUID()
    return (id, id.uuidString)
}

func decodeVersionPing(_ data: Data) throws -> PingPayload {
    try JSONDecoder().decode(PingPayload.self, from: data)
}

struct PingPayload: Decodable {
    struct Properties: Decodable {
        let kind: String
        let channel: String
        let previous: String?
        let processPersonProfile: Bool
        let geoIPDisable: Bool
        enum CodingKeys: String, CodingKey {
            case kind, channel, previous
            case processPersonProfile = "$process_person_profile"
            case geoIPDisable = "$geoip_disable"
        }
    }
    let event: String
    let uuid: String
    let timestamp: String
    let distinctID: String
    enum CodingKeys: String, CodingKey {
        case event, uuid, timestamp, properties
        case distinctID = "distinct_id"
    }
    let properties: Properties
}

private enum StatsTestError: Error { case updateTimedOut }

@MainActor
func waitForStats(_ model: StatsModel, until matches: (UsageStats) -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !matches(model.stats) {
        guard ContinuousClock.now < deadline else { throw StatsTestError.updateTimedOut }
        try await Task.sleep(for: .milliseconds(10))
    }
}

func settleStats() async throws {
    try await Task.sleep(for: .milliseconds(100))
}

final class StatsTestClock: Sendable {
    private let date = Mutex(Calendar.current.startOfDay(for: Date()).addingTimeInterval(43_200))
    var timestamp: Double { now().timeIntervalSince1970 }
    func now() -> Date { date.withLock { $0 } }
    func nextDay() { date.withLock { $0 = Calendar.current.date(byAdding: .day, value: 1, to: $0)! } }
}

func notifyStatsDayChanged() {
    NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
}

let listCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    calendar.locale = Locale(identifier: "en_GB")
    return calendar
}()

let listNow = listDate(day: 22, hour: 15)

func listDate(day: Int, hour: Int, minute: Int = 0, year: Int = 2026) -> Date {
    listCalendar.date(from: DateComponents(year: year, month: 10, day: day, hour: hour, minute: minute))!
}

func listDate(secondsBeforeNow seconds: Double) -> Date {
    listNow.addingTimeInterval(-seconds)
}

@MainActor
func editActionsHandled(byPanelFor keys: [(String, NSEvent.ModifierFlags)]) -> [String] {
    final class Recorder: NSView {
        var actions: [String] = []
        override var acceptsFirstResponder: Bool { true }
        @objc func cut(_ sender: Any?) { actions.append("cut") }
        @objc func copy(_ sender: Any?) { actions.append("copy") }
        @objc func paste(_ sender: Any?) { actions.append("paste") }
        @objc override func selectAll(_ sender: Any?) { actions.append("selectAll") }
        @objc func undo(_ sender: Any?) { actions.append("undo") }
        @objc func redo(_ sender: Any?) { actions.append("redo") }
    }
    let panel = PopoverPanel()
    let recorder = Recorder()
    panel.contentView = recorder
    panel.makeFirstResponder(recorder)
    for (key, modifiers) in keys {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: panel.windowNumber,
            context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: 0
        )!
        _ = panel.performKeyEquivalent(with: event)
    }
    return recorder.actions
}

func compilesAsAppleScript(_ source: String) -> Bool {
    var error: NSDictionary?
    return NSAppleScript(source: source)?.compileAndReturnError(&error) == true
}

@MainActor
func audioConfigurationChangeReturnsWhileMainThreadIsBlocked() -> Bool {
    let posted = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: nil)
        posted.signal()
    }
    return posted.wait(timeout: .now() + 1) == .success
}

func blockCurrentThread(seconds: Double) {
    Thread.sleep(forTimeInterval: seconds)
}
