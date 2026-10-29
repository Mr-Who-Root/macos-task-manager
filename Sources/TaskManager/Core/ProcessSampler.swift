import Darwin
import Foundation

enum ProcState: Sendable {
    case running, sleeping, stopped, zombie, idle
}

struct ProcessSample: Identifiable, Hashable, Sendable {
    let pid: Int32
    let ppid: Int32
    let uid: UInt32
    let user: String
    let name: String
    let path: String?
    let startTime: Date
    let state: ProcState
    let isTranslated: Bool
    let nice: Int32
    /// True when libproc refused access (another user's process) and figures came from `ps`.
    let restricted: Bool

    var cpu: Double = 0              // percent of the whole machine, 0...100
    var cpuTime: Double = 0          // seconds
    var memory: UInt64 = 0           // physical footprint (or RSS when restricted)
    var diskReadRate: Double = 0     // bytes/s
    var diskWriteRate: Double = 0
    var netRate: Double = 0          // bytes/s
    /// Energy macOS accounts to the process, as watts (0 when unreadable or on Intel).
    var power: Double = 0
    /// Averages over about two minutes, for "Power usage trend".
    var powerTrend: Double = 0
    var cpuTrend: Double = 0
    var idleWakeups: Double = 0      // per second
    var threads: Int = 0
    /// Base scheduling priority (4 = background/throttled, 31 = default); 0 when unknown.
    var basePriority: Int32 = 0
    /// True while a process the user put in efficiency mode is still at background priority.
    var efficiencyMode = false

    // Deltas since the previous sample, used for App history.
    var cpuDelta: Double = 0
    var diskDelta: Double = 0
    var netDelta: Double = 0
    var energyDelta: Double = 0      // joules

    var id: Int32 { pid }
    var diskRate: Double { diskReadRate + diskWriteRate }
    var isSuspended: Bool { state == .stopped }

    /// Text for the Processes tab "Status" column (blank when nothing notable).
    var statusText: String {
        switch state {
        case .stopped: return "Suspended"
        case .zombie: return "Not responding"
        default: return efficiencyMode ? "Efficiency mode" : ""
        }
    }

    /// Text for the Details tab "Status" column.
    var detailStatus: String {
        switch state {
        case .stopped: return "Suspended"
        case .zombie: return "Zombie"
        default: return efficiencyMode ? "Efficiency mode" : "Running"
        }
    }

    var architecture: String {
        if isTranslated { return "x64 (Rosetta)" }
        #if arch(arm64)
        return "ARM64"
        #else
        return "x64"
        #endif
    }

    var priorityName: String { Self.priorityName(nice) }

    static func priorityName(_ nice: Int32) -> String {
        switch nice {
        case ..<(-10): return "High"
        case ..<0: return "Above normal"
        case 0: return "Normal"
        case 1..<10: return "Below normal"
        default: return "Low"
        }
    }
}

/// Collects per-process statistics. Not thread-safe: use from a single serial queue.
final class ProcessSampler {
    private struct Previous {
        let start: Date
        let cpuNs: UInt64
        let diskRead: UInt64
        let diskWrite: UInt64
        let netBytes: UInt64
        let energyNJ: UInt64
        let idleWakeups: UInt64
        let powerTrend: Double
        let cpuTrend: Double
        /// Seconds the trends cover so far, up to `trendWindow`.
        let trendSpan: Double
    }

    private static let translatedFlag: Int32 = 0x0002_0000  // P_TRANSLATED
    /// Windows averages "Power usage trend" over two minutes.
    private static let trendWindow: Double = 120

    /// True once any process has reported energy. Apple silicon accounts energy per process; Intel Macs don't.
    private(set) var energyAvailable = false
    private var previous: [Int32: Previous] = [:]
    private var lastUptime: UInt64 = 0
    private var paths: [Int32: (start: Date, path: String?)] = [:]
    private var users: [UInt32: String] = [:]
    private var restrictedThreads: [Int32: Int] = [:]
    private var tick = 0
    private let nsPerAbsoluteTick: Double
    private let cpuCount: Double

    init() {
        var timebase = mach_timebase_info()
        mach_timebase_info(&timebase)
        nsPerAbsoluteTick = Double(timebase.numer) / Double(timebase.denom)
        cpuCount = Double(max(ProcessInfo.processInfo.activeProcessorCount, 1))
    }

    /// `efficient` holds EfficiencyStore keys for processes the user put in efficiency mode.
    func sample(efficient: Set<String> = []) -> [ProcessSample] {
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = lastUptime == 0 ? 0 : Double(now &- lastUptime) / 1_000_000_000
        lastUptime = now
        tick += 1

        let kinfos = Self.kernelProcessList()
        let netBytes = Self.networkBytesByPID()

        var samples: [ProcessSample] = []
        samples.reserveCapacity(kinfos.count)
        var cpuNs: [Int32: UInt64] = [:]
        var disk: [Int32: (read: UInt64, write: UInt64)] = [:]
        var energy: [Int32: (nanojoules: UInt64, idleWakeups: UInt64)] = [:]
        var anyRestricted = false

        for kp in kinfos {
            let pid = kp.kp_proc.p_pid
            let tv = kp.kp_proc.p_un.__p_starttime
            let start = Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
            let uid = kp.kp_eproc.e_ucred.cr_uid
            let path = executablePath(pid: pid, start: start)
            let name = path.map { ($0 as NSString).lastPathComponent } ?? Self.command(kp)

            var usage = rusage_info_v6()
            let readable = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
                }
            } == 0

            var sample = ProcessSample(
                pid: pid,
                ppid: kp.kp_eproc.e_ppid,
                uid: uid,
                user: userName(uid),
                name: name,
                path: path,
                startTime: start,
                state: Self.state(kp.kp_proc.p_stat),
                isTranslated: kp.kp_proc.p_flag & Self.translatedFlag != 0,
                nice: Int32(kp.kp_proc.p_nice),
                restricted: !readable
            )

            if readable {
                cpuNs[pid] = UInt64(Double(usage.ri_user_time &+ usage.ri_system_time) * nsPerAbsoluteTick)
                sample.memory = usage.ri_phys_footprint
                disk[pid] = (usage.ri_diskio_bytesread, usage.ri_diskio_byteswritten)
                energy[pid] = (usage.ri_energy_nj, usage.ri_pkg_idle_wkups)
                if usage.ri_energy_nj > 0 { energyAvailable = true }
                var info = proc_taskinfo()
                if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size)) > 0 {
                    sample.threads = Int(info.pti_threadnum)
                    sample.basePriority = info.pti_priority
                }
            } else {
                anyRestricted = true
            }
            samples.append(sample)
        }

        // /bin/ps is setuid root, so it can see other users' processes that libproc hides from us.
        if anyRestricted {
            let ps = Self.psStatistics()
            if tick % 5 == 1 || restrictedThreads.isEmpty {
                restrictedThreads = Self.threadCountsFromPS()
            }
            for i in samples.indices where samples[i].restricted {
                let pid = samples[i].pid
                if let stats = ps[pid] {
                    cpuNs[pid] = stats.cpuNs
                    samples[i].memory = stats.rss
                    samples[i].basePriority = stats.priority
                }
                samples[i].threads = restrictedThreads[pid] ?? 0
            }
        }

        if !efficient.isEmpty {
            for i in samples.indices {
                let key = EfficiencyStore.key(pid: samples[i].pid, startTime: samples[i].startTime)
                let priority = samples[i].basePriority
                samples[i].efficiencyMode = efficient.contains(key) && priority > 0 && priority <= EfficiencyStore.backgroundPriority
            }
        }

        var next: [Int32: Previous] = [:]
        next.reserveCapacity(samples.count)
        for i in samples.indices {
            let pid = samples[i].pid
            let cpu = cpuNs[pid] ?? 0
            let io = disk[pid] ?? (0, 0)
            let net = netBytes[pid] ?? 0
            let power = energy[pid] ?? (0, 0)
            samples[i].cpuTime = Double(cpu) / 1_000_000_000
            var trendSpan = 0.0

            if let old = previous[pid], old.start == samples[i].startTime, elapsed > 0 {
                let dCPU = cpu >= old.cpuNs ? Double(cpu - old.cpuNs) / 1_000_000_000 : 0
                let dRead = io.read >= old.diskRead ? Double(io.read - old.diskRead) : 0
                let dWrite = io.write >= old.diskWrite ? Double(io.write - old.diskWrite) : 0
                // nettop reports bytes of live flows; when flows close the total can drop.
                let dNet = net >= old.netBytes ? Double(net - old.netBytes) : Double(net)
                samples[i].cpu = min(100, dCPU / elapsed / cpuCount * 100)
                samples[i].cpuDelta = dCPU
                samples[i].diskReadRate = dRead / elapsed
                samples[i].diskWriteRate = dWrite / elapsed
                samples[i].diskDelta = dRead + dWrite
                samples[i].netRate = dNet / elapsed
                samples[i].netDelta = dNet
                let dEnergy = power.nanojoules >= old.energyNJ ? Double(power.nanojoules - old.energyNJ) / 1_000_000_000 : 0
                samples[i].power = dEnergy / elapsed
                samples[i].energyDelta = dEnergy
                samples[i].idleWakeups = power.idleWakeups >= old.idleWakeups ? Double(power.idleWakeups - old.idleWakeups) / elapsed : 0
                // A running mean until the window is full, then an exponential average over it.
                trendSpan = min(old.trendSpan + elapsed, Self.trendWindow)
                let weight = elapsed / trendSpan
                samples[i].powerTrend = old.powerTrend + (samples[i].power - old.powerTrend) * weight
                samples[i].cpuTrend = old.cpuTrend + (samples[i].cpu - old.cpuTrend) * weight
            }
            next[pid] = Previous(
                start: samples[i].startTime, cpuNs: cpu, diskRead: io.read, diskWrite: io.write, netBytes: net,
                energyNJ: power.nanojoules, idleWakeups: power.idleWakeups,
                powerTrend: samples[i].powerTrend, cpuTrend: samples[i].cpuTrend, trendSpan: trendSpan
            )
        }
        previous = next
        if tick % 30 == 0 {
            paths = paths.filter { next[$0.key] != nil }
        }
        return samples
    }

    // MARK: - Helpers

    private func executablePath(pid: Int32, start: Date) -> String? {
        if let cached = paths[pid], cached.start == start { return cached.path }
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        let path = length > 0 ? String(decoding: buffer.prefix(Int(length)), as: UTF8.self) : nil
        paths[pid] = (start, path)
        return path
    }

    private func userName(_ uid: UInt32) -> String {
        if let name = users[uid] { return name }
        let name = getpwuid(uid).map { String(cString: $0.pointee.pw_name) } ?? String(uid)
        users[uid] = name
        return name
    }

    private static func command(_ kp: kinfo_proc) -> String {
        var comm = kp.kp_proc.p_comm
        return withUnsafeBytes(of: &comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    private static func state(_ stat: CChar) -> ProcState {
        switch Int32(stat) {
        case SIDL: return .idle
        case SRUN: return .running
        case SSTOP: return .stopped
        case SZOMB: return .zombie
        default: return .sleeping
        }
    }

    static func kernelProcessList() -> [kinfo_proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        for _ in 0..<3 {
            var size = 0
            guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return [] }
            let capacity = size / MemoryLayout<kinfo_proc>.stride + 32
            var procs = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
            size = capacity * MemoryLayout<kinfo_proc>.stride
            if sysctl(&mib, 4, &procs, &size, nil, 0) == 0 {
                return Array(procs.prefix(size / MemoryLayout<kinfo_proc>.stride))
            }
            if errno != ENOMEM { return [] }
        }
        return []
    }

    private static func psStatistics() -> [Int32: (rss: UInt64, cpuNs: UInt64, priority: Int32)] {
        let output = Shell.run("/bin/ps", ["-axo", "pid=,rss=,time=,pri="]).output
        var result: [Int32: (rss: UInt64, cpuNs: UInt64, priority: Int32)] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3, let pid = Int32(parts[0]), let rss = UInt64(parts[1]) else { continue }
            // "pri" looks like "31T" or "4"; keep the number.
            let priority = parts.count >= 4 ? Int32(parts[3].prefix { $0.isNumber }) ?? 0 : 0
            result[pid] = (rss * 1024, UInt64(parseCPUTime(parts[2]) * 1_000_000_000), priority)
        }
        return result
    }

    /// Parses ps "time" values such as "133:37.54" or "1-02:03:04".
    static func parseCPUTime(_ text: Substring) -> Double {
        var days = 0.0
        var rest = text
        if let dash = text.firstIndex(of: "-") {
            days = Double(text[..<dash]) ?? 0
            rest = text[text.index(after: dash)...]
        }
        var total = 0.0
        for component in rest.split(separator: ":") {
            total = total * 60 + (Double(component) ?? 0)
        }
        return days * 86_400 + total
    }

    /// `ps -axM` prints one line per thread; count them per PID.
    private static func threadCountsFromPS() -> [Int32: Int] {
        let output = Shell.run("/bin/ps", ["-axM"]).output
        var lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        guard let header = lines.first, let pidRange = header.range(of: "PID") else { return [:] }
        let pidEnd = header.distance(from: header.startIndex, to: pidRange.upperBound)
        lines.removeFirst()
        var counts: [Int32: Int] = [:]
        for line in lines {
            if let token = line.prefix(pidEnd).split(separator: " ").last, let pid = Int32(token) {
                counts[pid, default: 0] += 1
            }
        }
        return counts
    }

    /// Bytes in + out per process for currently open flows, via nettop.
    private static func networkBytesByPID() -> [Int32: UInt64] {
        let output = Shell.run("/usr/bin/nettop", ["-P", "-L", "1", "-x", "-n", "-J", "bytes_in,bytes_out"]).output
        var result: [Int32: UInt64] = [:]
        for line in output.split(separator: "\n").dropFirst() {
            // "name.pid,bytes_in,bytes_out," — the name itself may contain dots or commas.
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 4 else { continue }
            let n = fields.count
            let label = fields[0..<(n - 3)].joined(separator: ",")
            guard let dot = label.lastIndex(of: "."), let pid = Int32(label[label.index(after: dot)...]) else { continue }
            result[pid, default: 0] += (UInt64(fields[n - 3]) ?? 0) + (UInt64(fields[n - 2]) ?? 0)
        }
        return result
    }
}
