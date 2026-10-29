import Darwin
import Foundation
import IOKit.ps
import TaskManagerShared
import WidgetKit

struct StatsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// True when Task Manager is running and sharing processes, sensors and history.
    let isLive: Bool
}

struct StatsProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatsEntry {
        StatsEntry(date: Date(), snapshot: .sample, isLive: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatsEntry) -> Void) {
        completion(context.isPreview && WidgetSnapshotStore.read() == nil ? placeholder(in: context) : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatsEntry>) -> Void) {
        let entry = currentEntry()
        // Task Manager also asks WidgetKit to reload while it runs; this is the fallback cadence.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(entry.isLive ? 60 : 300))))
    }

    private func currentEntry() -> StatsEntry {
        let now = Date()
        if let shared = WidgetSnapshotStore.read(), now.timeIntervalSince(shared.date) < 180 {
            return StatsEntry(date: now, snapshot: shared, isLive: true)
        }
        // Task Manager isn't running: measure what the sandbox allows.
        var snapshot = FallbackSampler.sample()
        if let stale = WidgetSnapshotStore.read() {
            snapshot.design = stale.design
            snapshot.accent = stale.accent
            snapshot.fahrenheit = stale.fahrenheit
            // Health and the 24-hour history change slowly, so keep the app's last figures.
            if var battery = snapshot.battery, let old = stale.battery {
                battery.health = old.health
                battery.condition = old.condition
                battery.cycleCount = old.cycleCount
                battery.designCycleCount = old.designCycleCount
                battery.levels = old.levels.filter { now.timeIntervalSince($0.time) < 24 * 3600 }
                snapshot.battery = battery
            }
        }
        return StatsEntry(date: now, snapshot: snapshot, isLive: false)
    }
}

/// CPU, memory, disk and network figures the sandboxed extension can read on its own.
enum FallbackSampler {
    static func sample() -> WidgetSnapshot {
        let ticksBefore = cpuTicks()
        let netBefore = interfaceBytes()
        usleep(400_000)
        let ticksAfter = cpuTicks()
        let netAfter = interfaceBytes()

        var cpu = 0.0
        if let a = ticksBefore, let b = ticksAfter {
            let busy = Double((b.busy &- a.busy))
            let total = Double((b.total &- a.total))
            cpu = total > 0 ? busy / total : 0
        }
        let memory = memoryStats()
        var fs = statfs()
        let hasDisk = statfs("/", &fs) == 0
        let total = hasDisk ? UInt64(fs.f_blocks) * UInt64(fs.f_bsize) : 0
        let free = hasDisk ? UInt64(fs.f_bavail) * UInt64(fs.f_bsize) : 0

        var snapshot = WidgetSnapshot(
            date: Date(), design: "windows11", accent: "automatic", fahrenheit: false,
            cpu: cpu, cpuHistory: [], perCore: [], cpuName: sysctlString("machdep.cpu.brand_string") ?? "CPU",
            processCount: 0, threadCount: 0, uptime: uptime(),
            memoryUsed: memory.used, memoryTotal: ProcessInfo.processInfo.physicalMemory, memoryCompressed: memory.compressed,
            memoryCached: memory.cached, swapUsed: 0, memoryPressure: "", memoryHistory: [],
            gpu: nil, gpuName: "GPU", gpuHistory: [],
            diskName: "Macintosh HD", diskTotal: total, diskFree: free, diskRead: 0, diskWrite: 0,
            networkSend: max(0, Double(netAfter.sent &- netBefore.sent)) / 0.4,
            networkReceive: max(0, Double(netAfter.received &- netBefore.received)) / 0.4,
            networkSendHistory: [], networkReceiveHistory: [],
            topApps: [], temperatures: [], fans: [], thermalState: ""
        )
        snapshot.battery = battery()
        return snapshot
    }

    /// IOPowerSources works inside the widget's sandbox, so charge and time left stay live without Task Manager.
    static func battery() -> WidgetSnapshot.Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            func int(_ key: String) -> Int? { (d[key] as? NSNumber)?.intValue }
            var battery = WidgetSnapshot.Battery()
            let maximum = Double(int(kIOPSMaxCapacityKey) ?? 100)
            battery.charge = maximum > 0 ? min(max(Double(int(kIOPSCurrentCapacityKey) ?? 0) / maximum, 0), 1) : 0
            battery.isCharging = d[kIOPSIsChargingKey] as? Bool ?? false
            battery.pluggedIn = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            battery.status = WidgetSnapshot.Battery.status(
                charging: battery.isCharging, pluggedIn: battery.pluggedIn,
                fullyCharged: d[kIOPSIsChargedKey] as? Bool ?? false, charge: battery.charge
            )
            if let minutes = int(kIOPSTimeToEmptyKey), minutes > 0, minutes < 65_535, !battery.pluggedIn { battery.timeToEmpty = minutes }
            if let minutes = int(kIOPSTimeToFullChargeKey), minutes > 0, minutes < 65_535, battery.isCharging { battery.timeToFull = minutes }
            battery.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled || (d["LPM Active"] as? NSNumber)?.boolValue == true
            if battery.pluggedIn, let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
                battery.adapterWatts = (adapter[kIOPSPowerAdapterWattsKey] as? NSNumber)?.doubleValue
                battery.adapterName = (adapter["Name"] as? String)?.trimmingCharacters(in: .whitespaces)
            }
            return battery
        }
        return nil
    }

    private static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS, let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)) }
        var busy: UInt64 = 0, total: UInt64 = 0
        for core in 0..<Int(count) {
            let base = core * Int(CPU_STATE_MAX)
            let user = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            let system = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            let nice = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            let idle = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            busy += user + system + nice
            total += user + system + nice + idle
        }
        return (busy, total)
    }

    private static func memoryStats() -> (used: UInt64, compressed: UInt64, cached: UInt64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return (0, 0, 0) }
        let page = UInt64(vm_kernel_page_size)
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = (internalPages > purgeable ? internalPages - purgeable : 0) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let used = app + UInt64(stats.wire_count) * page + compressed
        return (used, compressed, (UInt64(stats.external_page_count) + purgeable) * page)
    }

    private static func interfaceBytes() -> (sent: UInt64, received: UInt64) {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return (0, 0) }
        defer { freeifaddrs(list) }
        var sent: UInt64 = 0, received: UInt64 = 0
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, Int32(address.pointee.sa_family) == AF_LINK,
                  Int32(entry.ifa_flags) & IFF_LOOPBACK == 0,
                  let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            sent += UInt64(data.pointee.ifi_obytes)
            received += UInt64(data.pointee.ifi_ibytes)
        }
        return (sent, received)
    }

    private static func uptime() -> TimeInterval {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return 0 }
        return Date().timeIntervalSince1970 - Double(tv.tv_sec)
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }
}

extension WidgetSnapshot {
    /// Shown in the widget gallery before Task Manager has shared anything.
    static var sample: WidgetSnapshot {
        let wave: [Double] = (0..<60).map { (i: Int) -> Double in
            let x = Double(i)
            let slow: Double = 0.12 * sin(x / 5)
            let fast: Double = 0.05 * cos(x / 2)
            return 0.18 + slow + fast
        }
        var sample = WidgetSnapshot(
            date: Date(), design: "windows11", accent: "automatic", fahrenheit: false,
            cpu: 0.23, cpuHistory: wave, perCore: [0.42, 0.31, 0.25, 0.18, 0.12, 0.09, 0.3, 0.22, 0.05, 0.04, 0.08, 0.03],
            cpuName: "Apple silicon", processCount: 612, threadCount: 2_940, uptime: 3 * 86_400 + 4 * 3_600,
            memoryUsed: 14_500_000_000, memoryTotal: 24_000_000_000, memoryCompressed: 3_200_000_000, memoryCached: 5_100_000_000,
            swapUsed: 1_100_000_000, memoryPressure: "Normal", memoryHistory: wave.map { (v: Double) -> Double in 0.55 + v * 0.2 },
            gpu: 0.12, gpuName: "GPU", gpuHistory: wave.map { (v: Double) -> Double in v * 0.5 },
            diskName: "Macintosh HD", diskTotal: 494_000_000_000, diskFree: 182_000_000_000, diskRead: 1_200_000, diskWrite: 340_000,
            networkSend: 42_000, networkReceive: 1_350_000,
            networkSendHistory: wave.map { (v: Double) -> Double in v * 80_000 },
            networkReceiveHistory: wave.map { (v: Double) -> Double in v * 2_400_000 },
            topApps: [
                .init(name: "Safari", cpu: 6.4, memory: 1_284_000_000, icon: nil),
                .init(name: "Xcode", cpu: 4.1, memory: 3_912_000_000, icon: nil),
                .init(name: "Music", cpu: 1.2, memory: 212_000_000, icon: nil),
                .init(name: "Finder", cpu: 0.3, memory: 146_000_000, icon: nil),
                .init(name: "Mail", cpu: 0.2, memory: 318_000_000, icon: nil),
            ],
            temperatures: [
                .init(name: "CPU", symbol: "cpu", celsius: 52), .init(name: "GPU", symbol: "cube.transparent", celsius: 46),
                .init(name: "SSD", symbol: "internaldrive", celsius: 35), .init(name: "Battery", symbol: "battery.75percent", celsius: 31),
                .init(name: "SoC", symbol: "square.grid.3x3.square", celsius: 48), .init(name: "Memory", symbol: "memorychip", celsius: 41),
                .init(name: "Wi-Fi", symbol: "wifi", celsius: 38), .init(name: "Airflow", symbol: "wind", celsius: 33),
                .init(name: "Power", symbol: "bolt", celsius: 44),
            ],
            fans: [0], thermalState: "Nominal"
        )
        var battery = WidgetSnapshot.Battery()
        battery.charge = 0.72
        battery.status = "On battery power"
        battery.timeToEmpty = 312
        battery.health = 0.96
        battery.condition = "Normal"
        battery.cycleCount = 148
        battery.designCycleCount = 1_000
        battery.temperature = 31
        battery.powerDraw = 7.4
        battery.powerHistory = wave.map { (v: Double) -> Double in 5 + v * 12 }
        battery.batteryPower = -7.4
        // Down from full overnight on battery, then charging, then on battery again.
        let end = Date(timeIntervalSinceReferenceDate: (Date().timeIntervalSinceReferenceDate / 900).rounded(.down) * 900)
        battery.levels = (0..<96).compactMap { (i: Int) -> WidgetSnapshot.Level? in
            guard !(40..<52).contains(i) else { return nil }
            let charging = (24..<40).contains(i)
            let step = Double(i)
            var charge: Double
            if i < 24 {
                charge = 1 - step * 0.022
            } else if charging {
                charge = 0.47 + (step - 24) * 0.028
            } else {
                charge = 0.92 - (step - 52) * 0.0045
            }
            let time = end.addingTimeInterval((step - 95) * 900)
            return WidgetSnapshot.Level(time: time, charge: min(charge, 1), pluggedIn: charging)
        }
        sample.battery = battery
        sample.powerApps = [
            .init(name: "Safari", watts: 1.42, usage: "Moderate", heat: 0.5, keepsAwake: true, icon: nil),
            .init(name: "Xcode", watts: 0.86, usage: "Moderate", heat: 0.5, keepsAwake: false, icon: nil),
            .init(name: "Music", watts: 0.31, usage: "Low", heat: 0.25, keepsAwake: true, icon: nil),
            .init(name: "Messages", watts: 0.12, usage: "Low", heat: 0.25, keepsAwake: false, icon: nil),
            .init(name: "Photos", watts: 0.09, usage: "Very low", heat: 0, keepsAwake: false, icon: nil),
            .init(name: "Mail", watts: 0.04, usage: "Very low", heat: 0, keepsAwake: false, icon: nil),
            .init(name: "Notes", watts: 0.03, usage: "Very low", heat: 0, keepsAwake: false, icon: nil),
            .init(name: "Calendar", watts: 0.02, usage: "Very low", heat: 0, keepsAwake: false, icon: nil),
            .init(name: "Finder", watts: 0.02, usage: "Very low", heat: 0, keepsAwake: false, icon: nil),
        ]
        sample.sleepBlockers = [
            .init(name: "Safari", reason: "Video Wake Lock", keepsDisplayOn: true, icon: nil),
            .init(name: "Music", reason: "Playing audio", keepsDisplayOn: false, icon: nil),
        ]
        sample.memoryApps = [
            .init(name: "Xcode", cpu: 4.1, memory: 3_912_000_000, icon: nil),
            .init(name: "Safari", cpu: 6.4, memory: 1_284_000_000, icon: nil),
            .init(name: "Mail", cpu: 0.2, memory: 318_000_000, icon: nil),
            .init(name: "Music", cpu: 1.2, memory: 212_000_000, icon: nil),
        ]
        sample.diskReadHistory = wave.map { (v: Double) -> Double in v * 6_000_000 }
        sample.diskWriteHistory = wave.reversed().map { (v: Double) -> Double in v * 2_500_000 }
        sample.gpuCores = 16
        return sample
    }
}
