import Darwin
import Foundation

enum LaunchTimer {
    static func millisecondsSinceProcessStart() -> Int {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0 else {
            Log.app.error("Process start time unavailable")
            return 0
        }
        let start = info.kp_proc.p_un.__p_starttime
        let startDate = Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
        return Int(Date().timeIntervalSince(startDate) * 1000)
    }
}
