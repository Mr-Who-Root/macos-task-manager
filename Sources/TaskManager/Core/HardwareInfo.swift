import Foundation
import IOKit
import Metal

/// Static facts about the machine, read once.
struct HardwareInfo: Sendable {
    static let shared = HardwareInfo()

    let cpuName: String
    let modelIdentifier: String
    let physicalCores: Int
    let logicalCores: Int
    let performanceCores: Int
    let efficiencyCores: Int
    let performanceMaxHz: Double?
    let efficiencyMaxHz: Double?
    let l1Cache: UInt64
    let l2Cache: UInt64
    let l3Cache: UInt64
    let memorySize: UInt64
    let virtualization: Bool
    let bootTime: Date
    let osVersion: String
    let gpuName: String
    let gpuMemoryBudget: UInt64
    let metalSupport: String

    var maxSpeedHz: Double? { performanceMaxHz ?? efficiencyMaxHz }

    private init() {
        cpuName = Sysctl.string("machdep.cpu.brand_string") ?? "CPU"
        modelIdentifier = Sysctl.string("hw.model") ?? "Mac"
        physicalCores = Int(Sysctl.int("hw.physicalcpu") ?? 1)
        logicalCores = Int(Sysctl.int("hw.logicalcpu") ?? 1)
        memorySize = ProcessInfo.processInfo.physicalMemory
        virtualization = (Sysctl.int("kern.hv_support") ?? 0) == 1
        bootTime = Sysctl.bootTime() ?? Date()
        let v = ProcessInfo.processInfo.operatingSystemVersion
        osVersion = "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")

        let levels = Int(Sysctl.int("hw.nperflevels") ?? 1)
        if levels > 1 {
            performanceCores = Int(Sysctl.int("hw.perflevel0.physicalcpu") ?? 0)
            efficiencyCores = Int(Sysctl.int("hw.perflevel1.physicalcpu") ?? 0)
        } else {
            performanceCores = physicalCores
            efficiencyCores = 0
        }

        // Cache totals across all cores/clusters, like Windows reports them.
        var l1: UInt64 = 0, l2: UInt64 = 0
        if levels > 1 {
            for level in 0..<levels {
                let prefix = "hw.perflevel\(level)"
                let cores = UInt64(Sysctl.int("\(prefix).physicalcpu") ?? 0)
                let l1Size = UInt64((Sysctl.int("\(prefix).l1icachesize") ?? 0) + (Sysctl.int("\(prefix).l1dcachesize") ?? 0))
                let l2Size = UInt64(Sysctl.int("\(prefix).l2cachesize") ?? 0)
                let perL2 = UInt64(max(Sysctl.int("\(prefix).cpusperl2") ?? Int64(cores), 1))
                l1 += cores * l1Size
                l2 += max(cores / perL2, 1) * l2Size
            }
        } else {
            l1 = UInt64(physicalCores) * UInt64((Sysctl.int("hw.l1icachesize") ?? 0) + (Sysctl.int("hw.l1dcachesize") ?? 0))
            l2 = UInt64(Sysctl.int("hw.l2cachesize") ?? 0)
        }
        l1Cache = l1
        l2Cache = l2
        l3Cache = UInt64(Sysctl.int("hw.l3cachesize") ?? 0)

        let frequencies = Self.clusterMaxFrequencies()
        performanceMaxHz = frequencies.performance ?? Sysctl.int("hw.cpufrequency_max").map(Double.init)
        efficiencyMaxHz = frequencies.efficiency

        if let device = MTLCreateSystemDefaultDevice() {
            gpuName = device.name
            gpuMemoryBudget = device.recommendedMaxWorkingSetSize
            if device.supportsFamily(.metal3) {
                metalSupport = "Metal 3 or later"
            } else {
                metalSupport = "Metal 2"
            }
        } else {
            gpuName = "GPU"
            gpuMemoryBudget = 0
            metalSupport = "Unavailable"
        }
    }

    /// Apple silicon exposes each cluster's DVFS table on the "pmgr" registry entry.
    private static func clusterMaxFrequencies() -> (performance: Double?, efficiency: Double?) {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("pmgr"))
        guard entry != 0 else { return (nil, nil) }
        defer { IOObjectRelease(entry) }
        func maxFrequency(_ key: String) -> Double? {
            guard let data = SystemSampler.property(entry, key) as? Data, data.count >= 8 else { return nil }
            let values = data.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
            let frequencies = stride(from: 0, to: values.count, by: 2).map { Double(values[$0]) }
            guard let top = frequencies.max(), top > 0 else { return nil }
            // M1–M3 publish Hz; M4 and later publish kHz.
            return top > 100_000_000 ? top : top * 1_000
        }
        return (maxFrequency("voltage-states5-sram"), maxFrequency("voltage-states1-sram"))
    }
}
