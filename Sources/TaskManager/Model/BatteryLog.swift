import Foundation
import Observation

/// Battery level and power draw, one point a minute for the last 24 hours, recorded while
/// Task Manager runs and saved between launches.
@Observable @MainActor
final class BatteryLog {
    struct Point: Codable, Hashable {
        let time: Date          // start of the minute
        let charge: Double      // 0...1
        let pluggedIn: Bool
        /// Average whole-Mac power draw over the minute, in watts.
        let power: Double?
    }

    static let span: TimeInterval = 24 * 3600

    private(set) var points: [Point] = []

    @ObservationIgnored private var minute: Date?
    @ObservationIgnored private var charge = 0.0
    @ObservationIgnored private var pluggedIn = false
    @ObservationIgnored private var powerSum = 0.0
    @ObservationIgnored private var powerCount = 0
    @ObservationIgnored private var unsaved = 0
    @ObservationIgnored private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        let directory = support.appendingPathComponent("TaskManager", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("BatteryLog.json")
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode([Point].self, from: data) {
            let cutoff = Date().addingTimeInterval(-Self.span)
            points = saved.filter { $0.time > cutoff }
        }
    }

    func record(_ battery: BatterySnapshot, at now: Date = Date()) {
        guard battery.isPresent else { return }
        let start = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
        if let minute, minute != start { flush() }
        minute = start
        charge = battery.charge
        pluggedIn = battery.externalConnected
        if let draw = battery.powerDraw {
            powerSum += draw
            powerCount += 1
        }
    }

    /// Writes the log, including the minute in progress.
    func save() {
        flush()
        write()
    }

    private func flush() {
        guard let minute else { return }
        self.minute = nil
        points.append(Point(time: minute, charge: charge, pluggedIn: pluggedIn, power: powerCount > 0 ? powerSum / Double(powerCount) : nil))
        let cutoff = Date().addingTimeInterval(-Self.span)
        if let first = points.first, first.time <= cutoff { points.removeAll { $0.time <= cutoff } }
        powerSum = 0
        powerCount = 0
        unsaved += 1
        if unsaved >= 10 { write() }
    }

    private func write() {
        guard unsaved > 0 else { return }
        unsaved = 0
        if let data = try? JSONEncoder().encode(points) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
