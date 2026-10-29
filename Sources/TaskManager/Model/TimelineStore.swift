import Foundation
import Observation

/// What the Mac was doing, one record a minute for the last 24 hours: system totals and the apps
/// behind them, plus notable events. Recorded while Task Manager runs and saved between launches.
@Observable @MainActor
final class TimelineStore {
    struct Minute: Codable, Identifiable, Hashable {
        let time: Date              // start of the minute
        let cpu: Double             // 0...1
        let memory: Double          // 0...1
        let disk: Double            // bytes/s
        let network: Double         // bytes/s
        let power: Double?          // W, whole Mac
        let temperature: Double?    // °C, CPU
        let apps: [App]
        var events: [String]

        var id: Date { time }

        struct App: Codable, Hashable, Identifiable {
            let key: String         // App history key: a bundle path, or "exe:" and a path
            let name: String
            let cpu: Double         // percent of the machine
            let memory: UInt64
            let power: Double?      // W
            let disk: Double        // bytes/s
            let network: Double     // bytes/s

            var id: String { key }
            /// The bundle or executable to draw an icon for.
            var iconPath: String { key.hasPrefix("exe:") ? String(key.dropFirst(4)) : key }
        }
    }

    enum Metric: String, CaseIterable, Identifiable {
        case cpu, memory, disk, network, power

        var id: String { rawValue }
        var title: String {
            switch self {
            case .cpu: return "CPU"
            case .memory: return "Memory"
            case .disk: return "Disk"
            case .network: return "Network"
            case .power: return "Power"
            }
        }

        func value(_ minute: Minute) -> Double? {
            switch self {
            case .cpu: return minute.cpu
            case .memory: return minute.memory
            case .disk: return minute.disk
            case .network: return minute.network
            case .power: return minute.power
            }
        }

        func value(_ app: Minute.App) -> Double {
            switch self {
            case .cpu: return app.cpu
            case .memory: return Double(app.memory)
            case .disk: return app.disk
            case .network: return app.network
            case .power: return app.power ?? 0
            }
        }
    }

    static let span: TimeInterval = 24 * 3600

    private(set) var minutes: [Minute] = []

    @ObservationIgnored private var accumulator = Accumulator()
    @ObservationIgnored private var unsaved = 0
    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
            let directory = support.appendingPathComponent("TaskManager", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("Timeline.json")
        }
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: self.fileURL), let saved = try? decoder.decode([Minute].self, from: data) {
            let cutoff = Date().addingTimeInterval(-Self.span)
            minutes = saved.filter { $0.time > cutoff }
        }
    }

    /// Adds one sample. Called every update; a minute is written when the next one starts.
    func record(_ sample: Sample, at now: Date = Date()) {
        let start = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
        if let minute = accumulator.minute, minute != start { flush() }
        accumulator.add(sample, minute: start)
    }

    /// Notes something that happened, such as an app that stopped responding.
    func note(_ event: String) {
        if !accumulator.events.contains(event) { accumulator.events.append(event) }
    }

    func save() {
        flush()
        write()
    }

    private func flush() {
        guard let minute = accumulator.finish() else { return }
        minutes.append(minute)
        let cutoff = minute.time.addingTimeInterval(-Self.span)
        if let first = minutes.first, first.time <= cutoff { minutes.removeAll { $0.time <= cutoff } }
        unsaved += 1
        if unsaved >= 10 { write() }
    }

    private func write() {
        guard unsaved > 0 else { return }
        unsaved = 0
        if let data = try? JSONEncoder().encode(minutes) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: Accumulating a minute

    struct Sample {
        var cpu: Double
        var memory: Double
        var disk: Double
        var network: Double
        var power: Double?
        var temperature: Double?
        var apps: [(key: String, name: String, cpu: Double, memory: UInt64, power: Double?, disk: Double, network: Double)]
    }

    struct Accumulator {
        private(set) var minute: Date?
        var events: [String] = []
        private var count = 0
        private var cpu = 0.0, memory = 0.0, disk = 0.0, network = 0.0
        private var power = 0.0, powerCount = 0
        private var temperature = 0.0, temperatureCount = 0
        private var apps: [String: (name: String, cpu: Double, memory: UInt64, power: Double, hasPower: Bool, disk: Double, network: Double, count: Int)] = [:]

        mutating func add(_ sample: Sample, minute: Date) {
            self.minute = minute
            count += 1
            cpu += sample.cpu
            memory += sample.memory
            disk += sample.disk
            network += sample.network
            if let p = sample.power { power += p; powerCount += 1 }
            if let t = sample.temperature { temperature += t; temperatureCount += 1 }
            for app in sample.apps {
                var entry = apps[app.key] ?? (app.name, 0, 0, 0, false, 0, 0, 0)
                entry.cpu += app.cpu
                entry.memory = max(entry.memory, app.memory)
                if let p = app.power { entry.power += p; entry.hasPower = true }
                entry.disk += app.disk
                entry.network += app.network
                entry.count += 1
                apps[app.key] = entry
            }
        }

        /// The finished minute, keeping the apps that stood out on any measure.
        mutating func finish() -> Minute? {
            guard let minute, count > 0 else { return nil }
            let n = Double(count)
            let averaged = apps.map { key, e in
                Minute.App(key: key, name: e.name, cpu: e.cpu / n, memory: e.memory, power: e.hasPower ? e.power / n : nil,
                           disk: e.disk / n, network: e.network / n)
            }
            var keep: [String: Minute.App] = [:]
            func top(_ count: Int, by value: (Minute.App) -> Double, atLeast minimum: Double) {
                for app in averaged.sorted(by: { value($0) > value($1) }).prefix(count) where value(app) >= minimum {
                    keep[app.key] = app
                }
            }
            top(6, by: \.cpu, atLeast: 0.05)
            top(4, by: { Double($0.memory) }, atLeast: 0)
            top(3, by: { $0.power ?? 0 }, atLeast: 0.01)
            top(3, by: \.disk, atLeast: 1_024)
            top(3, by: \.network, atLeast: 1_024)
            let result = Minute(
                time: minute, cpu: cpu / n, memory: memory / n, disk: disk / n, network: network / n,
                power: powerCount > 0 ? power / Double(powerCount) : nil,
                temperature: temperatureCount > 0 ? temperature / Double(temperatureCount) : nil,
                apps: keep.values.sorted { $0.cpu > $1.cpu }, events: events
            )
            self = Accumulator()
            return result
        }
    }
}
