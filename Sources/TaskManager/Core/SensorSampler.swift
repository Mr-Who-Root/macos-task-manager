import Darwin
import Foundation
import IOKit

enum SensorComponent: String, CaseIterable, Sendable, Codable {
    case cpuPerformance, cpuEfficiency, cpu, gpu, soc, memory, ssd, battery, wireless, airflow, power, other

    var title: String {
        switch self {
        case .cpuPerformance: return "CPU performance cores"
        case .cpuEfficiency: return "CPU efficiency cores"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .soc: return "SoC die"
        case .memory: return "Memory"
        case .ssd: return "SSD"
        case .battery: return "Battery"
        case .wireless: return "Wi-Fi"
        case .airflow: return "Airflow"
        case .power: return "Power delivery"
        case .other: return "Other sensors"
        }
    }

    var shortTitle: String {
        switch self {
        case .cpuPerformance: return "P-cores"
        case .cpuEfficiency: return "E-cores"
        case .soc: return "SoC"
        case .wireless: return "Wi-Fi"
        case .power: return "Power"
        case .other: return "Other"
        default: return title
        }
    }

    var symbol: String {
        switch self {
        case .cpuPerformance, .cpuEfficiency, .cpu: return "cpu"
        case .gpu: return "cube.transparent"
        case .soc: return "square.grid.3x3.square"
        case .memory: return "memorychip"
        case .ssd: return "internaldrive"
        case .battery: return "battery.75percent"
        case .wireless: return "wifi"
        case .airflow: return "wind"
        case .power: return "bolt"
        case .other: return "thermometer.medium"
        }
    }
}

struct SensorReading: Identifiable, Sendable {
    let id: String          // "smc:Tp1j" or "hid:PMU tdie1"
    let name: String
    let source: String      // SMC key or HID product name
    let component: SensorComponent
    let celsius: Double
}

struct FanReading: Identifiable, Sendable {
    let id: Int
    let rpm: Double
    let minimum: Double
    let maximum: Double

    var fraction: Double { maximum > minimum ? max(0, min(1, (rpm - minimum) / (maximum - minimum))) : 0 }
}

struct ComponentTemperature: Identifiable, Sendable {
    let component: SensorComponent
    let average: Double
    let hottest: Double
    let count: Int
    var id: SensorComponent { component }
}

struct SensorSnapshot: Sendable {
    var readings: [SensorReading] = []
    /// Components whose sensors are all reporting the SMC's "powered down" value right now.
    var idleComponents: [SensorComponent] = []
    var fans: [FanReading] = []
    /// ProcessInfo.ThermalState raw value: 0 nominal … 3 critical.
    var thermalState = 0

    var components: [ComponentTemperature] {
        let grouped = Dictionary(grouping: readings, by: \.component)
        return SensorComponent.allCases.compactMap { component in
            guard let values = grouped[component]?.map(\.celsius), !values.isEmpty else { return nil }
            return ComponentTemperature(
                component: component,
                average: values.reduce(0, +) / Double(values.count),
                hottest: values.max() ?? 0,
                count: values.count
            )
        }
    }

    /// The figure people usually mean by "CPU temperature".
    var cpuTemperature: Double? {
        let cpu = components.filter { [.cpuPerformance, .cpuEfficiency, .cpu].contains($0.component) }
        if let hottest = cpu.map(\.average).max() { return hottest }
        return components.first { $0.component == .soc }?.average
    }

    var thermalStateText: String {
        switch thermalState {
        case 1: return "Fair"
        case 2: return "Serious"
        case 3: return "Critical"
        default: return "Nominal"
        }
    }
}

/// Reads temperature sensors (HID event system + SMC) and fans. Use from one serial queue.
final class SensorSampler {
    private let hid = HIDTemperatureReader()
    private let smc = SMCReader()
    private var smcSensors: [(key: String, component: SensorComponent, info: SMCReader.KeyInfo)] = []
    private var knownComponents: Set<SensorComponent> = []
    private var fanCount = 0
    private var enumerated = false

    func sample() -> SensorSnapshot {
        if !enumerated {
            enumerated = true
            discoverSMCSensors()
        }
        var snapshot = SensorSnapshot()
        snapshot.thermalState = ProcessInfo.processInfo.thermalState.rawValue

        for (name, value) in hid.read() where Self.isPlausible(value) {
            guard let component = Self.component(forHIDName: name) else { continue }
            snapshot.readings.append(SensorReading(id: "hid:\(name)", name: Self.friendlyHIDName(name), source: name, component: component, celsius: value))
        }

        // Power-gated cores report a fixed round value (40.0 on Apple silicon) instead of a
        // temperature, so drop any round value shared by several sensors of one component.
        var values: [(sensor: (key: String, component: SensorComponent, info: SMCReader.KeyInfo), celsius: Double)] = []
        for sensor in smcSensors {
            if let value = smc.readNumber(sensor.key, info: sensor.info), Self.isPlausible(value) {
                values.append((sensor, value))
            }
        }
        var roundCounts: [String: Int] = [:]
        for entry in values where entry.celsius == entry.celsius.rounded() {
            roundCounts["\(entry.sensor.component.rawValue)|\(entry.celsius)", default: 0] += 1
        }
        var counters: [SensorComponent: Int] = [:]
        for entry in values where roundCounts["\(entry.sensor.component.rawValue)|\(entry.celsius)", default: 0] < 4 {
            let component = entry.sensor.component
            counters[component, default: 0] += 1
            snapshot.readings.append(SensorReading(
                id: "smc:\(entry.sensor.key)",
                name: "\(component.shortTitle) sensor \(counters[component]!)",
                source: entry.sensor.key,
                component: component,
                celsius: entry.celsius
            ))
        }
        let live = Set(snapshot.readings.map(\.component))
        knownComponents.formUnion(live)
        knownComponents.formUnion(Set(smcSensors.map(\.component)).filter { [.cpuPerformance, .cpuEfficiency].contains($0) })
        snapshot.idleComponents = SensorComponent.allCases.filter { knownComponents.contains($0) && !live.contains($0) }

        for i in 0..<fanCount {
            func value(_ suffix: String) -> Double {
                let key = "F\(i)\(suffix)"
                guard let info = smc.keyInfo(key) else { return 0 }
                return smc.readNumber(key, info: info) ?? 0
            }
            snapshot.fans.append(FanReading(id: i, rpm: value("Ac"), minimum: value("Mn"), maximum: value("Mx")))
        }
        return snapshot
    }

    private static func isPlausible(_ celsius: Double) -> Bool { celsius > 10 && celsius < 130 }

    /// Lists the SMC's temperature keys once.
    private func discoverSMCSensors() {
        guard smc.isOpen else { return }
        fanCount = Int(smc.keyInfo("FNum").flatMap { smc.readNumber("FNum", info: $0) } ?? 0)
        smcSensors = smc.allKeys().compactMap { key in
            guard key.hasPrefix("T"), let component = Self.component(forSMCKey: key),
                  let info = smc.keyInfo(key), SMCReader.isNumeric(info.type),
                  smc.readNumber(key, info: info) != nil else { return nil }
            return (key: key, component: component, info: info)
        }
    }

    static func component(forSMCKey key: String) -> SensorComponent? {
        let chars = Array(key)
        guard chars.count == 4 else { return nil }
        let prefix = String(chars[0...1])
        switch prefix {
        case "Tp": return .cpuPerformance
        case "Te": return .cpuEfficiency
        case "TC": return .cpu
        case "Tg", "TG": return .gpu
        case "Tm", "TM": return .memory
        case "TH": return .ssd
        case "TB": return .battery
        case "TW": return .wireless
        case "Ta", "TA": return .airflow
        case "TV": return .power
        case "TP", "TR", "TU": return .soc
        case "Ts", "TS", "TD", "Tf", "TN": return .other
        default: return nil
        }
    }

    static func component(forHIDName name: String) -> SensorComponent? {
        let lower = name.lowercased()
        if lower.contains("tcal") || lower.contains("tdev") { return nil }
        if lower.contains("pacc") { return .cpuPerformance }
        if lower.contains("eacc") { return .cpuEfficiency }
        if lower.hasPrefix("gpu") { return .gpu }
        if lower.contains("nand") { return .ssd }
        if lower.contains("battery") || lower.contains("gas gauge") { return .battery }
        if lower.contains("tdie") || lower.hasPrefix("soc") || lower.contains("ane") { return .soc }
        return .other
    }

    private static func friendlyHIDName(_ name: String) -> String {
        if name.hasPrefix("PMU tdie") { return "Die sensor " + name.dropFirst("PMU tdie".count) }
        if name.hasPrefix("NAND") { return "SSD controller" }
        if name == "gas gauge battery" { return "Battery cell" }
        return name.replacingOccurrences(of: " MTR Temp Sensor", with: " sensor ")
    }
}

// MARK: - HID temperature services (no public API; symbols resolved at runtime)

private final class HIDTemperatureReader {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatchingFn = @convention(c) (AnyObject, CFDictionary) -> Int32
    private typealias CopyServicesFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyEventFn = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias FloatValueFn = @convention(c) (AnyObject, Int32) -> Double
    private typealias CopyPropertyFn = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?

    private static let temperatureEvent: Int64 = 15
    private var client: AnyObject?
    private var services: [AnyObject] = []
    private var lastRefresh = Date.distantPast
    private let copyServices: CopyServicesFn?
    private let copyEvent: CopyEventFn?
    private let floatValue: FloatValueFn?
    private let copyProperty: CopyPropertyFn?

    init() {
        let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }
        copyServices = symbol("IOHIDEventSystemClientCopyServices", as: CopyServicesFn.self)
        copyEvent = symbol("IOHIDServiceClientCopyEvent", as: CopyEventFn.self)
        floatValue = symbol("IOHIDEventGetFloatValue", as: FloatValueFn.self)
        copyProperty = symbol("IOHIDServiceClientCopyProperty", as: CopyPropertyFn.self)
        if let create = symbol("IOHIDEventSystemClientCreate", as: CreateFn.self),
           let setMatching = symbol("IOHIDEventSystemClientSetMatching", as: SetMatchingFn.self),
           let client = create(kCFAllocatorDefault)?.takeRetainedValue() {
            // Apple vendor usage page 0xff00, usage 5 = temperature sensors.
            _ = setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
            self.client = client
        }
    }

    func read() -> [(String, Double)] {
        guard let client, let copyServices, let copyEvent, let floatValue, let copyProperty else { return [] }
        if Date().timeIntervalSince(lastRefresh) > 60 {
            services = copyServices(client)?.takeRetainedValue() as? [AnyObject] ?? []
            lastRefresh = Date()
        }
        var result: [(String, Double)] = []
        var seen: Set<String> = []
        for service in services {
            guard let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String,
                  !seen.contains(name),
                  let event = copyEvent(service, Self.temperatureEvent, 0, 0)?.takeRetainedValue() else { continue }
            seen.insert(name)
            result.append((name, floatValue(event, Int32(Self.temperatureEvent << 16))))
        }
        return result
    }
}

// MARK: - SMC

final class SMCReader {
    struct KeyInfo: Sendable {
        let size: UInt32
        let type: String
    }

    private struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
    private struct PowerLimit { var version: UInt16 = 0, length: UInt16 = 0; var cpu: UInt32 = 0, gpu: UInt32 = 0, memory: UInt32 = 0 }
    // Padded to match the C struct (Swift packs the next field after `size`, C after the stride).
    private struct RawKeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var attributes: UInt8 = 0; var padding: (UInt8, UInt8, UInt8) = (0, 0, 0) }
    private typealias Bytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                               UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    private struct Parameters {
        var key: UInt32 = 0
        var version = Version()
        var powerLimit = PowerLimit()
        var keyInfo = RawKeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var command: UInt8 = 0
        var index: UInt32 = 0
        var bytes: Bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private enum Command: UInt8 { case readBytes = 5, readIndex = 8, readKeyInfo = 9 }

    private var connection: io_connect_t = 0
    private var infoCache: [String: KeyInfo] = [:]
    var isOpen: Bool { connection != 0 }

    init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &connection) != KERN_SUCCESS { connection = 0 }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    private func call(_ input: inout Parameters) -> Parameters? {
        guard connection != 0 else { return nil }
        var output = Parameters()
        var size = MemoryLayout<Parameters>.stride
        let result = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<Parameters>.stride, &output, &size)
        return result == KERN_SUCCESS && output.result == 0 ? output : nil
    }

    private static func fourCC(_ key: String) -> UInt32 { key.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    private static func string(_ code: UInt32) -> String {
        String(bytes: [UInt8(code >> 24), UInt8((code >> 16) & 0xff), UInt8((code >> 8) & 0xff), UInt8(code & 0xff)], encoding: .ascii) ?? ""
    }

    func keyInfo(_ key: String) -> KeyInfo? {
        if let cached = infoCache[key] { return cached }
        var input = Parameters()
        input.key = Self.fourCC(key)
        input.command = Command.readKeyInfo.rawValue
        guard let output = call(&input) else { return nil }
        let info = KeyInfo(size: output.keyInfo.dataSize, type: Self.string(output.keyInfo.dataType))
        infoCache[key] = info
        return info
    }

    func allKeys() -> [String] {
        guard let countInfo = keyInfo("#KEY"), let bytes = readBytes("#KEY", info: countInfo), bytes.count >= 4 else { return [] }
        let count = Int(bytes[0]) << 24 | Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
        var keys: [String] = []
        keys.reserveCapacity(count)
        for index in 0..<count {
            var input = Parameters()
            input.command = Command.readIndex.rawValue
            input.index = UInt32(index)
            if let output = call(&input) { keys.append(Self.string(output.key)) }
        }
        return keys
    }

    private func readBytes(_ key: String, info: KeyInfo) -> [UInt8]? {
        var input = Parameters()
        input.key = Self.fourCC(key)
        input.keyInfo.dataSize = info.size
        input.command = Command.readBytes.rawValue
        guard let output = call(&input) else { return nil }
        return withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(min(info.size, 32)))) }
    }

    static func isNumeric(_ type: String) -> Bool {
        ["flt ", "sp78", "fpe2", "ui8 ", "ui16", "ui32", "sp87", "sp96"].contains(type)
    }

    /// Decodes the SMC's numeric formats (Apple silicon uses little-endian floats; Intel uses fixed point).
    func readNumber(_ key: String, info: KeyInfo) -> Double? {
        guard let b = readBytes(key, info: info), !b.isEmpty else { return nil }
        switch info.type {
        case "flt " where b.count >= 4:
            return Double(b.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        case "sp78" where b.count >= 2:
            return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256
        case "sp87" where b.count >= 2:
            return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 128
        case "sp96" where b.count >= 2:
            return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 64
        case "fpe2" where b.count >= 2:
            return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4
        case "ui8 ":
            return Double(b[0])
        case "ui16" where b.count >= 2:
            return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        case "ui32" where b.count >= 4:
            return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
        default:
            return nil
        }
    }
}
