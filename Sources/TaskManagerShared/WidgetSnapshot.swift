import Darwin
import Foundation

/// What the app shares with its widgets. Written by Task Manager every few seconds and read
/// by the (sandboxed) widget extension, which is allowed to read only this folder.
public struct WidgetSnapshot: Codable, Sendable {
    public struct App: Codable, Sendable {
        public var name: String
        public var cpu: Double            // percent of the whole machine
        public var memory: UInt64
        public var icon: Data?            // small PNG

        public init(name: String, cpu: Double, memory: UInt64, icon: Data?) {
            self.name = name
            self.cpu = cpu
            self.memory = memory
            self.icon = icon
        }
    }

    public struct Temperature: Codable, Sendable {
        public var name: String
        public var symbol: String
        public var celsius: Double

        public init(name: String, symbol: String, celsius: Double) {
            self.name = name
            self.symbol = symbol
            self.celsius = celsius
        }
    }

    public struct Battery: Codable, Sendable {
        public var charge: Double = 0                 // 0...1
        public var isCharging = false
        public var pluggedIn = false
        public var status = ""                        // "Charging", "On battery power", …
        public var timeToEmpty: Int?                  // minutes
        public var timeToFull: Int?
        public var health: Double?                    // 0...1
        public var condition: String?
        public var cycleCount: Int?
        public var designCycleCount: Int?
        public var temperature: Double?               // °C
        /// Whole-Mac power draw, in watts, and its recent history.
        public var powerDraw: Double?
        public var powerHistory: [Double] = []
        /// Watts into (+) or out of (−) the battery.
        public var batteryPower: Double?
        public var lowPowerMode = false
        public var adapterName: String?
        public var adapterWatts: Double?
        /// The level at the end of each 15 minutes over the last 24 hours.
        public var levels: [Level] = []

        public init() {}
    }

    public struct Level: Codable, Sendable {
        public var time: Date
        public var charge: Double                     // 0...1
        public var pluggedIn: Bool

        public init(time: Date, charge: Double, pluggedIn: Bool) {
            self.time = time
            self.charge = charge
            self.pluggedIn = pluggedIn
        }
    }

    /// An app on the battery usage list.
    public struct PowerApp: Codable, Sendable {
        public var name: String
        public var watts: Double?                     // nil where macOS doesn't account energy per app
        public var usage: String                      // "Very low" … "Very high"
        public var heat: Double                       // 0...1
        public var keepsAwake: Bool
        public var icon: Data?

        public init(name: String, watts: Double?, usage: String, heat: Double, keepsAwake: Bool, icon: Data?) {
            self.name = name
            self.watts = watts
            self.usage = usage
            self.heat = heat
            self.keepsAwake = keepsAwake
            self.icon = icon
        }
    }

    /// An app keeping the Mac (or its display) awake.
    public struct SleepBlocker: Codable, Sendable {
        public var name: String
        public var reason: String
        public var keepsDisplayOn: Bool
        public var icon: Data?

        public init(name: String, reason: String, keepsDisplayOn: Bool, icon: Data?) {
            self.name = name
            self.reason = reason
            self.keepsDisplayOn = keepsDisplayOn
            self.icon = icon
        }
    }

    public var date: Date
    public var design: String
    public var accent: String
    public var fahrenheit: Bool

    public var cpu: Double                // 0...1
    public var cpuHistory: [Double]
    public var perCore: [Double]
    public var cpuName: String
    public var processCount: Int
    public var threadCount: Int
    public var uptime: TimeInterval

    public var memoryUsed: UInt64
    public var memoryTotal: UInt64
    public var memoryCompressed: UInt64
    public var memoryCached: UInt64
    public var swapUsed: UInt64
    public var memoryPressure: String
    public var memoryHistory: [Double]

    public var gpu: Double?
    public var gpuName: String
    public var gpuHistory: [Double]

    public var diskName: String
    public var diskTotal: UInt64
    public var diskFree: UInt64
    public var diskRead: Double           // bytes/s
    public var diskWrite: Double

    public var networkSend: Double        // bytes/s
    public var networkReceive: Double
    public var networkSendHistory: [Double]
    public var networkReceiveHistory: [Double]

    public var topApps: [App]
    public var temperatures: [Temperature]
    public var fans: [Double]             // RPM
    public var thermalState: String

    // Added in 1.2. Optional so snapshots from earlier versions still decode.
    public var battery: Battery?
    public var powerApps: [PowerApp]?
    public var sleepBlockers: [SleepBlocker]?
    public var memoryApps: [App]?
    public var diskReadHistory: [Double]?
    public var diskWriteHistory: [Double]?
    public var gpuCores: Int?

    public init(
        date: Date, design: String, accent: String, fahrenheit: Bool,
        cpu: Double, cpuHistory: [Double], perCore: [Double], cpuName: String, processCount: Int, threadCount: Int, uptime: TimeInterval,
        memoryUsed: UInt64, memoryTotal: UInt64, memoryCompressed: UInt64, memoryCached: UInt64, swapUsed: UInt64,
        memoryPressure: String, memoryHistory: [Double],
        gpu: Double?, gpuName: String, gpuHistory: [Double],
        diskName: String, diskTotal: UInt64, diskFree: UInt64, diskRead: Double, diskWrite: Double,
        networkSend: Double, networkReceive: Double, networkSendHistory: [Double], networkReceiveHistory: [Double],
        topApps: [App], temperatures: [Temperature], fans: [Double], thermalState: String
    ) {
        self.date = date; self.design = design; self.accent = accent; self.fahrenheit = fahrenheit
        self.cpu = cpu; self.cpuHistory = cpuHistory; self.perCore = perCore; self.cpuName = cpuName
        self.processCount = processCount; self.threadCount = threadCount; self.uptime = uptime
        self.memoryUsed = memoryUsed; self.memoryTotal = memoryTotal; self.memoryCompressed = memoryCompressed
        self.memoryCached = memoryCached; self.swapUsed = swapUsed; self.memoryPressure = memoryPressure; self.memoryHistory = memoryHistory
        self.gpu = gpu; self.gpuName = gpuName; self.gpuHistory = gpuHistory
        self.diskName = diskName; self.diskTotal = diskTotal; self.diskFree = diskFree; self.diskRead = diskRead; self.diskWrite = diskWrite
        self.networkSend = networkSend; self.networkReceive = networkReceive
        self.networkSendHistory = networkSendHistory; self.networkReceiveHistory = networkReceiveHistory
        self.topApps = topApps; self.temperatures = temperatures; self.fans = fans; self.thermalState = thermalState
    }

    public var memoryFraction: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }
    public var diskUsedFraction: Double { diskTotal > 0 ? Double(diskTotal - min(diskFree, diskTotal)) / Double(diskTotal) : 0 }

    /// True when the snapshot came from a running Task Manager (rather than the widget's own fallback).
    public var hasLiveDetail: Bool { !topApps.isEmpty || !temperatures.isEmpty }
}

extension WidgetSnapshot.Battery {
    /// "Charging", "On battery power", "Fully charged" or "Plugged in, not charging".
    public static func status(charging: Bool, pluggedIn: Bool, fullyCharged: Bool, charge: Double) -> String {
        if charging { return "Charging" }
        if !pluggedIn { return "On battery power" }
        if fullyCharged || charge >= 0.995 { return "Fully charged" }
        return "Plugged in, not charging"
    }

    /// SF Symbol for the charge level.
    public static func symbol(charge: Double, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch charge {
        case ..<0.1: return "battery.0percent"
        case ..<0.38: return "battery.25percent"
        case ..<0.63: return "battery.50percent"
        case ..<0.88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    public var symbol: String { Self.symbol(charge: charge, charging: isCharging) }
}

public enum WidgetSnapshotStore {
    /// The user's real home folder (inside the sandbox, NSHomeDirectory points at the container).
    public static var realHome: String {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir { return String(cString: dir) }
        return NSHomeDirectory()
    }

    /// ~/Library/Application Support/TaskManager/widget-snapshot.json
    public static var url: URL {
        URL(fileURLWithPath: realHome)
            .appendingPathComponent("Library/Application Support/TaskManager", isDirectory: true)
            .appendingPathComponent("widget-snapshot.json")
    }

    public static func write(_ snapshot: WidgetSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public static func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// The URL scheme widgets use to open a page in the app, e.g. taskmanager://performance.
    public static let urlScheme = "taskmanager"
}
