import ApplicationServices
import Darwin
import Foundation

/// Finds apps that have stopped handling events, the way Windows marks them "Not responding":
/// either WindowServer has flagged them (the spinning pointer), or their main thread has been
/// fully busy for several seconds. Use from one serial queue.
final class HangDetector {
    struct Hang: Sendable, Equatable {
        let since: Date
        /// True when the main thread is spinning, rather than blocked.
        let busy: Bool
    }

    /// A main thread this busy counts as spinning; it stops counting only below `idleThreshold`,
    /// so brief dips (other work competing for the core, or `sample` pausing it) don't reset the clock.
    static let busyThreshold = 0.85
    static let idleThreshold = 0.5
    static let busySeconds: TimeInterval = 5

    private var last: [Int32: (cpu: UInt64, uptime: UInt64)] = [:]
    private var busySince: [Int32: Date] = [:]
    private var flaggedSince: [Int32: Date] = [:]
    private let windowServer = WindowServerProbe()

    /// `pids` are the apps with a Dock icon; background processes have no event loop to hang.
    func sample(_ pids: [Int32], now: Date = Date()) -> [Int32: Hang] {
        let uptime = DispatchTime.now().uptimeNanoseconds
        var next: [Int32: (cpu: UInt64, uptime: UInt64)] = [:]
        var result: [Int32: Hang] = [:]
        for pid in pids {
            if let cpu = Self.mainThreadCPU(pid) {
                next[pid] = (cpu, uptime)
                if let old = last[pid], uptime > old.uptime {
                    let busy = Double(cpu &- old.cpu) / Double(uptime - old.uptime)
                    busySince[pid] = Self.busySince(busySince[pid], busy: busy, now: now)
                }
            }
            flaggedSince[pid] = windowServer.isUnresponsive(pid) ? (flaggedSince[pid] ?? now) : nil
            if let hang = Self.verdict(flaggedSince: flaggedSince[pid], busySince: busySince[pid], now: now) {
                result[pid] = hang
            }
        }
        last = next
        busySince = busySince.filter { next[$0.key] != nil }
        flaggedSince = flaggedSince.filter { next[$0.key] != nil || result[$0.key] != nil }
        return result
    }

    /// When the main thread started spinning, given how busy it was over the last interval.
    static func busySince(_ since: Date?, busy: Double, now: Date) -> Date? {
        if busy >= busyThreshold { return since ?? now }
        return busy < idleThreshold ? nil : since
    }

    /// WindowServer's flag counts at once; a busy main thread only after `busySeconds`.
    static func verdict(flaggedSince: Date?, busySince: Date?, now: Date) -> Hang? {
        if let flaggedSince { return Hang(since: min(flaggedSince, busySince ?? flaggedSince), busy: busySince != nil) }
        if let busySince, now.timeIntervalSince(busySince) >= busySeconds { return Hang(since: busySince, busy: true) }
        return nil
    }

    /// CPU time of the process's first thread (the main thread), in nanoseconds.
    private static func mainThreadCPU(_ pid: Int32) -> UInt64? {
        var ids = [UInt64](repeating: 0, count: 64)
        let bytes = proc_pidinfo(pid, PROC_PIDLISTTHREADS, 0, &ids, Int32(ids.count * MemoryLayout<UInt64>.size))
        guard bytes > 0, let first = ids.first, first != 0 else { return nil }
        var info = proc_threadinfo()
        guard proc_pidinfo(pid, PROC_PIDTHREADINFO, first, &info, Int32(MemoryLayout<proc_threadinfo>.size)) > 0 else { return nil }
        return info.pth_user_time + info.pth_system_time
    }
}

/// WindowServer's own "this app isn't responding" flag (no public API; resolved at runtime).
private final class WindowServerProbe {
    private typealias ConnectionFn = @convention(c) () -> Int32
    private typealias UnresponsiveFn = @convention(c) (Int32, UnsafePointer<ProcessSerialNumber>) -> Bool
    private typealias ProcessForPIDFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

    private let connection: ConnectionFn?
    private let unresponsive: UnresponsiveFn?
    private let processForPID: ProcessForPIDFn?

    init() {
        let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
        let services = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW)
        connection = dlsym(skyLight, "SLSMainConnectionID").map { unsafeBitCast($0, to: ConnectionFn.self) }
        unresponsive = dlsym(skyLight, "SLSEventIsAppUnresponsive").map { unsafeBitCast($0, to: UnresponsiveFn.self) }
        processForPID = dlsym(services, "GetProcessForPID").map { unsafeBitCast($0, to: ProcessForPIDFn.self) }
    }

    func isUnresponsive(_ pid: Int32) -> Bool {
        guard let connection, let unresponsive, let processForPID else { return false }
        var psn = ProcessSerialNumber()
        guard processForPID(pid, &psn) == noErr else { return false }
        return unresponsive(connection(), &psn)
    }
}
