import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import TaskManagerShared

struct PowerAdapter: Sendable {
    var name: String
    var watts: Double?
    var voltage: Double?        // V
    var current: Double?        // A
    var manufacturer: String?
    var isWireless = false
}

/// A power assertion that keeps the Mac, or just its display, awake.
struct SleepAssertion: Identifiable, Sendable {
    let id: Int
    let pid: Int32
    let processName: String
    let reason: String
    let preventsDisplaySleep: Bool
    let since: Date?
}

struct BatterySnapshot: Sendable {
    var isPresent = false
    var charge: Double = 0                  // 0...1
    var isCharging = false
    var isFullyCharged = false
    var externalConnected = false
    /// Minutes; nil while macOS is still estimating or the figure doesn't apply.
    var timeToEmpty: Int?
    var timeToFull: Int?
    var cycleCount: Int?
    var designCycleCount: Int?
    var designCapacity: Double?             // mAh
    var fullChargeCapacity: Double?         // mAh, what a full charge holds today
    var nominalCapacity: Double?            // mAh
    var remainingCapacity: Double?          // mAh
    var voltage: Double?                    // V
    var amperage: Double?                   // A, negative while discharging
    var temperature: Double?                // °C, from the battery's gas gauge
    var cellVoltages: [Double] = []
    /// Whole-Mac power draw from the power telemetry, in watts.
    var systemPower: Double?
    /// Power coming in from the adapter, in watts.
    var adapterPower: Double?
    var condition: String?
    var optimizedCharging = false
    var serial: String?
    var deviceName: String?
    var manufacturer: String?
    var adapter: PowerAdapter?
    var lowPowerMode = false
    var assertions: [SleepAssertion] = []

    /// Watts into (+) or out of (−) the battery.
    var batteryPower: Double? {
        guard let voltage, let amperage else { return nil }
        return voltage * amperage
    }

    /// What the whole Mac is drawing: the telemetry figure, or the battery's discharge rate on battery power.
    var powerDraw: Double? {
        if let systemPower { return systemPower }
        if !externalConnected, let batteryPower, batteryPower < 0 { return -batteryPower }
        return nil
    }

    /// Maximum capacity relative to the design capacity, capped at 100% the way System Settings shows it.
    var health: Double? {
        guard let design = designCapacity, design > 0, let maximum = nominalCapacity ?? fullChargeCapacity else { return nil }
        return min(1, maximum / design)
    }

    var isOnBattery: Bool { isPresent && !externalConnected }

    var statusText: String {
        guard isPresent else { return "No battery" }
        return WidgetSnapshot.Battery.status(charging: isCharging, pluggedIn: externalConnected, fullyCharged: isFullyCharged, charge: charge)
    }

    var symbol: String { WidgetSnapshot.Battery.symbol(charge: charge, charging: isCharging) }
}

/// Windows Task Manager's "Power usage" levels.
enum PowerUsage: Int, Comparable, Sendable {
    case veryLow, low, moderate, high, veryHigh

    var title: String {
        switch self {
        case .veryLow: return "Very low"
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        case .veryHigh: return "Very high"
        }
    }

    /// 0...1 for the heat map.
    var heat: Double { Double(rawValue) / 4 }

    /// From the energy macOS accounts to a process, in watts.
    init(watts: Double) {
        switch watts {
        case ..<0.1: self = .veryLow
        case ..<0.5: self = .low
        case ..<1.5: self = .moderate
        case ..<4: self = .high
        default: self = .veryHigh
        }
    }

    /// Estimated from CPU use (percent of the whole machine) where there is no energy figure.
    init(cpuPercent: Double) {
        switch cpuPercent {
        case ..<1: self = .veryLow
        case ..<5: self = .low
        case ..<15: self = .moderate
        case ..<35: self = .high
        default: self = .veryHigh
        }
    }

    static func < (lhs: PowerUsage, rhs: PowerUsage) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Reads the battery (IOPowerSources and the AppleSmartBattery driver), the power adapter
/// and sleep assertions. Use from one serial queue.
final class BatterySampler {
    private var service: io_service_t = 0

    deinit {
        if service != 0 { IOObjectRelease(service) }
    }

    func sample() -> BatterySnapshot {
        var snapshot = BatterySnapshot()
        snapshot.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        snapshot.assertions = Self.sleepAssertions()
        readPowerSource(into: &snapshot)
        guard snapshot.isPresent else { return snapshot }
        readSmartBattery(into: &snapshot)
        if snapshot.externalConnected { snapshot.adapter = Self.adapter() }
        return snapshot
    }

    private func readPowerSource(into s: inout BatterySnapshot) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  d[kIOPSIsPresentKey] as? Bool ?? true else { continue }
            func int(_ key: String) -> Int? { (d[key] as? NSNumber)?.intValue }
            s.isPresent = true
            let current = Double(int(kIOPSCurrentCapacityKey) ?? 0)
            let maximum = Double(int(kIOPSMaxCapacityKey) ?? 100)
            s.charge = maximum > 0 ? min(max(current / maximum, 0), 1) : 0
            s.isCharging = d[kIOPSIsChargingKey] as? Bool ?? false
            s.isFullyCharged = d[kIOPSIsChargedKey] as? Bool ?? false
            s.externalConnected = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            // -1 means macOS is still calculating.
            if let minutes = int(kIOPSTimeToEmptyKey), minutes > 0, minutes < 65_535, !s.externalConnected { s.timeToEmpty = minutes }
            if let minutes = int(kIOPSTimeToFullChargeKey), minutes > 0, minutes < 65_535, s.isCharging { s.timeToFull = minutes }
            s.designCycleCount = int("DesignCycleCount")
            s.serial = d[kIOPSHardwareSerialNumberKey] as? String
            s.optimizedCharging = (d["Optimized Battery Charging Engaged"] as? NSNumber)?.boolValue ?? false
            if (d["LPM Active"] as? NSNumber)?.boolValue == true { s.lowPowerMode = true }
            // The condition key ("Check Battery", "Permanent Battery Failure", …) only appears when something is wrong.
            if !(d[kIOPSBatteryHealthConditionKey] as? String ?? "").isEmpty {
                s.condition = "Service recommended"
            } else if let health = d[kIOPSBatteryHealthKey] as? String {
                s.condition = health == kIOPSGoodValue ? "Normal" : "Service recommended"
            } else {
                s.condition = "Normal"
            }
            return
        }
    }

    /// Capacities, cycles, voltage and current. Key names moved between macOS releases, so each
    /// value is looked up at the top level and then in the BatteryData dictionary.
    private func readSmartBattery(into s: inout BatterySnapshot) {
        if service == 0 {
            service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        }
        guard service != 0 else { return }
        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        let data = property("BatteryData") as? [String: Any] ?? [:]
        func number(_ key: String) -> NSNumber? { property(key) as? NSNumber ?? data[key] as? NSNumber }
        func positive(_ key: String) -> Double? { number(key).map(\.doubleValue).flatMap { $0 > 0 ? $0 : nil } }

        s.cycleCount = number("CycleCount")?.intValue
        if let rated = number("DesignCycleCount9C")?.intValue, rated > 0 { s.designCycleCount = rated }
        s.designCapacity = positive("DesignCapacity")
        s.nominalCapacity = positive("NominalChargeCapacity")
        // Intel Macs report MaxCapacity and CurrentCapacity in mAh; Apple silicon uses a 0–100 scale.
        let legacyMaximum = positive("MaxCapacity").flatMap { $0 > 100 ? $0 : nil }
        s.fullChargeCapacity = positive("AppleRawMaxCapacity") ?? positive("FullChargeCapacity") ?? legacyMaximum
        s.remainingCapacity = positive("AppleRawCurrentCapacity") ?? positive("RemainingCapacity")
            ?? (legacyMaximum != nil ? positive("CurrentCapacity") : nil)
        if let millivolts = positive("Voltage") ?? positive("AppleRawBatteryVoltage") { s.voltage = millivolts / 1000 }
        // Signed, but some releases store negative values as unsigned 64-bit numbers.
        if let milliamps = number("Amperage")?.int64Value, (-50_000..<50_000).contains(milliamps) { s.amperage = Double(milliamps) / 1000 }
        if let centi = positive("Temperature") ?? positive("VirtualTemperature"), centi > 500, centi < 8_000 {
            s.temperature = centi / 100
        }
        s.cellVoltages = (data["CellVoltage"] as? [NSNumber] ?? []).map { $0.doubleValue / 1000 }.filter { $0 > 0 }
        s.deviceName = (property("DeviceName") as? String).flatMap { $0.isEmpty ? nil : $0 }
        s.manufacturer = (property("Manufacturer") as? String).flatMap { $0.isEmpty ? nil : $0 }
        if let serial = property("Serial") as? String, !serial.isEmpty { s.serial = serial }

        if let telemetry = property("PowerTelemetryData") as? [String: Any] {
            func watts(_ key: String) -> Double? {
                (telemetry[key] as? NSNumber).map { $0.doubleValue / 1000 }.flatMap { $0 > 0 && $0 < 1_000 ? $0 : nil }
            }
            s.systemPower = watts("SystemLoad")
            if s.externalConnected { s.adapterPower = watts("SystemPowerIn") }
        }
    }

    private static func adapter() -> PowerAdapter? {
        guard let d = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else { return nil }
        func number(_ key: String) -> Double? { (d[key] as? NSNumber)?.doubleValue }
        let watts = number(kIOPSPowerAdapterWattsKey).flatMap { $0 > 0 ? $0 : nil }
        var name = (d["Name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        if name.isEmpty { name = watts.map { "\(Int($0)) W power adapter" } ?? "Power adapter" }
        return PowerAdapter(
            name: name,
            watts: watts,
            voltage: number("AdapterVoltage").flatMap { $0 > 0 ? $0 / 1000 : nil },
            current: number(kIOPSPowerAdapterCurrentKey).flatMap { $0 > 0 ? $0 / 1000 : nil },
            manufacturer: (d["Manufacturer"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            isWireless: (d["IsWireless"] as? NSNumber)?.boolValue ?? false
        )
    }

    private static let systemSleepTypes: Set<String> = ["PreventUserIdleSystemSleep", "NoIdleSleepAssertion", "PreventSystemSleep"]
    private static let displaySleepTypes: Set<String> = ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"]

    /// Assertions apps hold to keep the Mac awake. powerd's own (such as "Prevent sleep while
    /// display is on") are system policy rather than something an app is doing, so they're left out.
    private static func sleepAssertions() -> [SleepAssertion] {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
        var result: [SleepAssertion] = []
        for (pid, assertions) in byProcess {
            for a in assertions {
                let type = a["AssertionTrueType"] as? String ?? a["AssertType"] as? String ?? ""
                let display = displaySleepTypes.contains(type)
                guard display || systemSleepTypes.contains(type), (a["AssertLevel"] as? NSNumber)?.intValue ?? 255 > 0 else { continue }
                let name = a["Process Name"] as? String ?? ""
                guard name != "powerd" else { continue }
                result.append(SleepAssertion(
                    id: (a["AssertionId"] as? NSNumber)?.intValue ?? result.count,
                    pid: pid.int32Value,
                    processName: name.isEmpty ? "PID \(pid)" : name,
                    reason: a["AssertName"] as? String ?? "",
                    preventsDisplaySleep: display,
                    since: a["AssertStartWhen"] as? Date
                ))
            }
        }
        return result.sorted { ($0.since ?? .distantFuture, $0.id) < ($1.since ?? .distantFuture, $1.id) }
    }
}
