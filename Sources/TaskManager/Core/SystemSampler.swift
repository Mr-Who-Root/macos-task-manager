import Darwin
import Foundation
import IOKit
import SystemConfiguration

struct CPUSnapshot: Sendable {
    var total: Double = 0          // 0...1
    var kernel: Double = 0         // 0...1
    var perCore: [Double] = []
    var perCoreKernel: [Double] = []
    var loadAverage: Double = 0
}

struct MemorySnapshot: Sendable {
    var total: UInt64 = ProcessInfo.processInfo.physicalMemory
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var pressure: Int = 1

    var used: UInt64 { app + wired + compressed }
    var free: UInt64 { total > used + cached ? total - used - cached : 0 }
    var available: UInt64 { total > used ? total - used : 0 }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    var pressureText: String {
        switch pressure {
        case 4: return "Critical"
        case 2: return "Warning"
        default: return "Normal"
        }
    }
}

struct DiskSnapshot: Identifiable, Sendable {
    let id: String              // BSD name, e.g. "disk0"
    var index: Int
    var model: String
    var volumes: [String]
    var isInternal: Bool
    var isSSD: Bool
    var interconnect: String
    var capacity: UInt64
    var formatted: UInt64
    var isSystemDisk: Bool
    var readRate: Double = 0    // bytes/s
    var writeRate: Double = 0
    var activeTime: Double = 0  // 0...1
    var responseTimeMs: Double = 0

    var title: String {
        volumes.isEmpty ? "Disk \(index)" : "Disk \(index) (\(volumes.joined(separator: ", ")))"
    }
    var kindText: String {
        if !isInternal && !isSSD { return "Removable" }
        return isSSD ? "SSD" : "HDD"
    }
}

struct NetworkSnapshot: Identifiable, Sendable {
    let id: String              // BSD name, e.g. "en0"
    var name: String
    var kind: String
    var ipv4: [String]
    var ipv6: [String]
    var linkSpeed: UInt64       // bits/s
    var sendRate: Double = 0    // bits/s
    var receiveRate: Double = 0
}

struct GPUSnapshot: Sendable {
    var name = "GPU"
    var cores: Int?
    var utilization: Double = 0  // 0...1
    var renderer: Double = 0
    var tiler: Double = 0
    var memoryUsed: UInt64 = 0
}

struct SystemSnapshot: Sendable {
    var cpu = CPUSnapshot()
    var memory = MemorySnapshot()
    var disks: [DiskSnapshot] = []
    var networks: [NetworkSnapshot] = []
    var gpu: GPUSnapshot?
    var sensors = SensorSnapshot()
}

/// Samples machine-wide counters. Not thread-safe: use from a single serial queue.
final class SystemSampler {
    private struct DiskCounters { let read: UInt64; let write: UInt64; let time: UInt64; let ops: UInt64 }
    private struct DiskMeta { let descendants: Set<String> }
    private struct NetMeta { let bsd: String; let name: String; let kind: String; let ipv4: [String]; let ipv6: [String] }

    private var previousTicks: [[UInt32]] = []
    private var previousDisk: [String: DiskCounters] = [:]
    private var previousNet: [String: (rx: UInt64, tx: UInt64)] = [:]
    private var diskMeta: [String: DiskMeta] = [:]
    private var volumes: [(bsd: String, name: String, isRoot: Bool, capacity: UInt64)] = []
    private var netMeta: [NetMeta] = []
    private let sensorSampler = SensorSampler()
    private var lastUptime: UInt64 = 0
    private var tick = 0

    func sample() -> SystemSnapshot {
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = lastUptime == 0 ? 0 : Double(now &- lastUptime) / 1_000_000_000
        lastUptime = now
        tick += 1
        if tick % 10 == 1 {
            diskMeta = [:]
            volumes = Self.mountedVolumes()
            netMeta = Self.networkInterfaces()
        }
        var snapshot = SystemSnapshot()
        snapshot.cpu = sampleCPU()
        snapshot.memory = Self.sampleMemory()
        snapshot.disks = sampleDisks(elapsed: elapsed)
        snapshot.networks = sampleNetworks(elapsed: elapsed)
        snapshot.gpu = Self.sampleGPU()
        snapshot.sensors = sensorSampler.sample()
        return snapshot
    }

    // MARK: CPU

    private func sampleCPU() -> CPUSnapshot {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return CPUSnapshot() }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let states = Int(CPU_STATE_MAX)
        var ticks: [[UInt32]] = []
        for core in 0..<Int(cpuCount) {
            ticks.append((0..<states).map { UInt32(bitPattern: info[core * states + $0]) })
        }
        defer { previousTicks = ticks }

        var snapshot = CPUSnapshot()
        var load = [Double](repeating: 0, count: 3)
        getloadavg(&load, 3)
        snapshot.loadAverage = load[0]
        guard previousTicks.count == ticks.count else {
            snapshot.perCore = Array(repeating: 0, count: ticks.count)
            snapshot.perCoreKernel = snapshot.perCore
            return snapshot
        }

        var busy = 0.0, kernel = 0.0, all = 0.0
        for (current, old) in zip(ticks, previousTicks) {
            let user = Double(current[Int(CPU_STATE_USER)] &- old[Int(CPU_STATE_USER)])
            let system = Double(current[Int(CPU_STATE_SYSTEM)] &- old[Int(CPU_STATE_SYSTEM)])
            let idle = Double(current[Int(CPU_STATE_IDLE)] &- old[Int(CPU_STATE_IDLE)])
            let nice = Double(current[Int(CPU_STATE_NICE)] &- old[Int(CPU_STATE_NICE)])
            let total = user + system + idle + nice
            snapshot.perCore.append(total > 0 ? (user + system + nice) / total : 0)
            snapshot.perCoreKernel.append(total > 0 ? system / total : 0)
            busy += user + system + nice
            kernel += system
            all += total
        }
        snapshot.total = all > 0 ? busy / all : 0
        snapshot.kernel = all > 0 ? kernel / all : 0
        return snapshot
    }

    // MARK: Memory

    private static func sampleMemory() -> MemorySnapshot {
        var memory = MemorySnapshot()
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            // Same breakdown Activity Monitor uses.
            let page = UInt64(vm_kernel_page_size)
            let internalPages = UInt64(stats.internal_page_count)
            let purgeable = UInt64(stats.purgeable_count)
            memory.app = (internalPages > purgeable ? internalPages - purgeable : 0) * page
            memory.wired = UInt64(stats.wire_count) * page
            memory.compressed = UInt64(stats.compressor_page_count) * page
            memory.cached = (UInt64(stats.external_page_count) + purgeable) * page
        }
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            memory.swapUsed = swap.xsu_used
            memory.swapTotal = swap.xsu_total
        }
        memory.pressure = Int(Sysctl.int("kern.memorystatus_vm_pressure_level") ?? 1)
        return memory
    }

    // MARK: Disks

    private func sampleDisks(elapsed: Double) -> [DiskSnapshot] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var disks: [DiskSnapshot] = []
        var counters: [String: DiskCounters] = [:]
        while true {
            let driver = IOIteratorNext(iterator)
            if driver == 0 { break }
            defer { IOObjectRelease(driver) }

            guard let media = Self.child(of: driver, conformingTo: "IOMedia") else { continue }
            defer { IOObjectRelease(media) }
            guard let bsd = Self.property(media, "BSD Name") as? String else { continue }

            var device: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(driver, kIOServicePlane, &device) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(device) }
            let characteristics = Self.property(device, "Device Characteristics") as? [String: Any] ?? [:]
            let protocolInfo = Self.property(device, "Protocol Characteristics") as? [String: Any] ?? [:]
            let location = protocolInfo["Physical Interconnect Location"] as? String ?? ""
            if location == "File" { continue }  // mounted disk images

            if diskMeta[bsd] == nil {
                diskMeta[bsd] = DiskMeta(descendants: Self.descendantBSDNames(of: media))
            }
            let descendants = diskMeta[bsd]?.descendants ?? []
            let owned = volumes.filter {
                (descendants.contains($0.bsd) || descendants.contains(Self.wholeDisk($0.bsd))) && !Self.hiddenVolumeNames.contains($0.name)
            }

            let stats = Self.property(driver, "Statistics") as? [String: Any] ?? [:]
            func number(_ key: String) -> UInt64 { (stats[key] as? NSNumber)?.uint64Value ?? 0 }
            let current = DiskCounters(
                read: number("Bytes (Read)"),
                write: number("Bytes (Write)"),
                time: number("Total Time (Read)") &+ number("Total Time (Write)"),
                ops: number("Operations (Read)") &+ number("Operations (Write)")
            )
            counters[bsd] = current

            let model = (characteristics["Product Name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? "Disk"
            var disk = DiskSnapshot(
                id: bsd,
                index: Int(bsd.dropFirst(4).prefix { $0.isNumber }) ?? disks.count,
                model: model,
                volumes: owned.map(\.name),
                isInternal: location == "Internal",
                isSSD: (characteristics["Medium Type"] as? String) == "Solid State",
                interconnect: protocolInfo["Physical Interconnect"] as? String ?? "Unknown",
                capacity: (Self.property(media, "Size") as? NSNumber)?.uint64Value ?? 0,
                formatted: owned.map(\.capacity).max() ?? 0,
                isSystemDisk: owned.contains { $0.isRoot }
            )
            if let old = previousDisk[bsd], elapsed > 0 {
                let dTime = current.time >= old.time ? Double(current.time - old.time) : 0
                let dOps = current.ops >= old.ops ? Double(current.ops - old.ops) : 0
                disk.readRate = current.read >= old.read ? Double(current.read - old.read) / elapsed : 0
                disk.writeRate = current.write >= old.write ? Double(current.write - old.write) / elapsed : 0
                disk.activeTime = min(1, dTime / (elapsed * 1_000_000_000))
                disk.responseTimeMs = dOps > 0 ? dTime / dOps / 1_000_000 : 0
            }
            disks.append(disk)
        }
        previousDisk = counters
        return disks.sorted { $0.index < $1.index }
    }

    /// Apple-internal volumes that macOS sometimes mounts under /Volumes.
    private static let hiddenVolumeNames: Set<String> = ["Recovery", "Preboot", "VM", "Update", "xarts", "iSCPreboot", "Hardware"]

    private static func wholeDisk(_ bsd: String) -> String {
        "disk" + bsd.dropFirst(4).prefix { $0.isNumber }
    }

    private static func child(of entry: io_registry_entry_t, conformingTo className: String) -> io_registry_entry_t? {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while true {
            let child = IOIteratorNext(iterator)
            if child == 0 { return nil }
            if IOObjectConformsTo(child, className) != 0 { return child }
            IOObjectRelease(child)
        }
    }

    private static func descendantBSDNames(of media: io_registry_entry_t) -> Set<String> {
        var names: Set<String> = []
        if let own = property(media, "BSD Name") as? String { names.insert(own) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(media, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else { return names }
        defer { IOObjectRelease(iterator) }
        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { break }
            if IOObjectConformsTo(entry, "IOMedia") != 0, let name = property(entry, "BSD Name") as? String {
                names.insert(name)
            }
            IOObjectRelease(entry)
        }
        return names
    }

    private static func mountedVolumes() -> [(bsd: String, name: String, isRoot: Bool, capacity: UInt64)] {
        var mounts: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&mounts, MNT_NOWAIT)
        guard count > 0, let mounts else { return [] }
        var result: [(bsd: String, name: String, isRoot: Bool, capacity: UInt64)] = []
        for i in 0..<Int(count) {
            var fs = mounts[i]
            let from = withUnsafeBytes(of: &fs.f_mntfromname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            let on = withUnsafeBytes(of: &fs.f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            guard from.hasPrefix("/dev/disk"), on == "/" || on.hasPrefix("/Volumes/") else { continue }
            let isRoot = on == "/"
            let name: String
            if isRoot {
                name = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName ?? "Macintosh HD"
            } else {
                name = (on as NSString).lastPathComponent
            }
            result.append((String(from.dropFirst(5)), name, isRoot, UInt64(fs.f_blocks) * UInt64(fs.f_bsize)))
        }
        return result
    }

    static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    // MARK: Network

    private func sampleNetworks(elapsed: Double) -> [NetworkSnapshot] {
        let counters = Self.interfaceCounters()
        var result: [NetworkSnapshot] = []
        for meta in netMeta {
            guard let c = counters[meta.bsd] else { continue }
            var snapshot = NetworkSnapshot(id: meta.bsd, name: meta.name, kind: meta.kind, ipv4: meta.ipv4, ipv6: meta.ipv6, linkSpeed: c.baud)
            if let old = previousNet[meta.bsd], elapsed > 0 {
                snapshot.receiveRate = c.rx >= old.rx ? Double(c.rx - old.rx) * 8 / elapsed : 0
                snapshot.sendRate = c.tx >= old.tx ? Double(c.tx - old.tx) * 8 / elapsed : 0
            }
            result.append(snapshot)
        }
        previousNet = counters.mapValues { ($0.rx, $0.tx) }
        return result
    }

    /// 64-bit interface byte counters from the routing socket (NET_RT_IFLIST2).
    private static func interfaceCounters() -> [String: (rx: UInt64, tx: UInt64, baud: UInt64)] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return [:] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return [:] }

        var result: [String: (rx: UInt64, tx: UInt64, baud: UInt64)] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(message.ifm_index), &name) != nil {
                        let key = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                        result[key] = (message.ifm_data.ifi_ibytes, message.ifm_data.ifi_obytes, message.ifm_data.ifi_baudrate)
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return result
    }

    private static func networkInterfaces() -> [NetMeta] {
        var addresses: [String: (v4: [String], v6: [String], up: Bool)] = [:]
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let name = String(cString: entry.ifa_name)
            let flags = Int32(entry.ifa_flags)
            var record = addresses[name] ?? ([], [], false)
            record.up = record.up || (flags & IFF_UP != 0 && flags & IFF_RUNNING != 0)
            if let address = entry.ifa_addr {
                let family = Int32(address.pointee.sa_family)
                if family == AF_INET || family == AF_INET6 {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        var text = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                        if let scope = text.firstIndex(of: "%") { text = String(text[..<scope]) }
                        if family == AF_INET { record.v4.append(text) } else { record.v6.append(text) }
                    }
                }
            }
            addresses[name] = record
        }

        var known: [String: (name: String, type: String)] = [:]
        if let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for interface in interfaces {
                guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
                let display = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? bsd
                let type = SCNetworkInterfaceGetInterfaceType(interface) as String? ?? ""
                known[bsd] = (display, type)
            }
        }

        var result: [NetMeta] = []
        for (bsd, record) in addresses where record.up && !bsd.hasPrefix("lo") {
            let routableV4 = record.v4.filter { !$0.hasPrefix("169.254.") }
            let routableV6 = record.v6.filter { !$0.lowercased().hasPrefix("fe80") }
            guard !routableV4.isEmpty || !routableV6.isEmpty else { continue }
            if let info = known[bsd] {
                let kind: String
                if info.type == kSCNetworkInterfaceTypeIEEE80211 as String {
                    kind = "Wi-Fi"
                } else if info.type == kSCNetworkInterfaceTypeEthernet as String {
                    kind = info.name.localizedCaseInsensitiveContains("bridge") ? "Bridge" : "Ethernet"
                } else {
                    kind = info.name
                }
                result.append(NetMeta(bsd: bsd, name: info.name, kind: kind, ipv4: record.v4, ipv6: routableV6))
            } else if (bsd.hasPrefix("utun") || bsd.hasPrefix("ipsec") || bsd.hasPrefix("ppp")) && !routableV4.isEmpty {
                result.append(NetMeta(bsd: bsd, name: "VPN (\(bsd))", kind: "VPN", ipv4: record.v4, ipv6: routableV6))
            }
        }
        let order = ["Wi-Fi": 0, "Ethernet": 1]
        return result.sorted { (order[$0.kind] ?? 2, $0.bsd) < (order[$1.kind] ?? 2, $1.bsd) }
    }

    // MARK: GPU

    private static func sampleGPU() -> GPUSnapshot? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { return nil }
            defer { IOObjectRelease(entry) }
            guard let stats = property(entry, "PerformanceStatistics") as? [String: Any] else { continue }
            func percent(_ key: String) -> Double { ((stats[key] as? NSNumber)?.doubleValue ?? 0) / 100 }
            var gpu = GPUSnapshot()
            if let model = property(entry, "model") as? String {
                gpu.name = model
            } else if let data = property(entry, "model") as? Data {
                gpu.name = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
            }
            gpu.cores = (property(entry, "gpu-core-count") as? NSNumber)?.intValue
            gpu.utilization = percent("Device Utilization %")
            gpu.renderer = percent("Renderer Utilization %")
            gpu.tiler = percent("Tiler Utilization %")
            gpu.memoryUsed = (stats["In use system memory"] as? NSNumber)?.uint64Value ?? 0
            return gpu
        }
    }
}
