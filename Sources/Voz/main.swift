import AppKit
import Foundation
import VozCore

let arguments = CommandLine.arguments

if let exitCode = await PackageCLI.run(arguments) {
    exit(exitCode)
}

if let exitCode = await Headless.run(arguments) {
    exit(exitCode)
}

let application = NSApplication.shared

if arguments.contains(IndicatorDemo.launchArgument) {
    application.setActivationPolicy(.accessory)
    let indicator = IndicatorController()
    Task {
        await IndicatorDemo.run(on: indicator)
        exit(0)
    }
    application.run()
}

let instance = SingleInstance()
guard instance.claim(waiting: LaunchAgent.launchedByLaunchd ? .seconds(5) : .zero) else {
    Log.app.notice("Another voz is running, exiting")
    exit(0)
}
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
