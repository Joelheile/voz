import AppKit
import Foundation

let arguments = CommandLine.arguments

if PackageCLI.handles(arguments) || Headless.handles(arguments) {
    Task {
        exit(PackageCLI.handles(arguments) ? await PackageCLI.run(arguments) : await Headless.run(arguments))
    }
    RunLoop.main.run()
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
    if !LaunchAgent.launchedByLaunchd { OpenRequest.send() }
    exit(0)
}
application.setActivationPolicy(.accessory)
if AppMover.shouldOffer {
    AppMover.offer()
}
let delegate = AppDelegate()
application.delegate = delegate
application.run()
