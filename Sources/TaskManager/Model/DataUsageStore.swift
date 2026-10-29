import Foundation
import Observation

/// Network data each app downloaded and uploaded, per day for the last month. Recorded while
/// Task Manager runs and saved between launches.
@Observable @MainActor
final class DataUsageStore {
    struct Usage: Codable, Hashable {
        var name: String
        var iconPath: String?
        var received: Double    // bytes
        var sent: Double
    }

    struct Total: Identifiable, Hashable {
        let id: String          // App history key
        let name: String
        let iconPath: String?
        let received: Double
        let sent: Double
        var total: Double { received + sent }
    }

    static let keepDays = 31

    /// "yyyy-MM-dd" → App history key → usage.
    private(set) var days: [String: [String: Usage]] = [:]

    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var lastSave = Date()
    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
            let directory = support.appendingPathComponent("TaskManager", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("DataUsage.json")
        }
        if let data = try? Data(contentsOf: self.fileURL), let saved = try? JSONDecoder().decode([String: [String: Usage]].self, from: data) {
            days = saved
        }
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func record(_ nodes: [ProcNode], at now: Date = Date()) {
        let active = nodes.filter { $0.netReceivedDelta > 0 || $0.netSentDelta > 0 }
        guard !active.isEmpty else { return }
        add(active.map { ($0.historyKey, $0.name, $0.iconPath, $0.netReceivedDelta, $0.netSentDelta) }, at: now)
    }

    func add(_ entries: [(key: String, name: String, iconPath: String?, received: Double, sent: Double)], at now: Date) {
        let day = Self.dayKey(now)
        var today = days[day] ?? [:]
        for entry in entries {
            var usage = today[entry.key] ?? Usage(name: entry.name, iconPath: entry.iconPath, received: 0, sent: 0)
            usage.name = entry.name
            usage.received += entry.received
            usage.sent += entry.sent
            today[entry.key] = usage
        }
        days[day] = today
        dirty = true
        if days.count > Self.keepDays {
            for key in days.keys.sorted().dropLast(Self.keepDays) { days[key] = nil }
        }
        if now.timeIntervalSince(lastSave) > 60 { save() }
    }

    /// Per-app totals over the last `count` days including today, largest first.
    func totals(days count: Int, now: Date = Date(), calendar: Calendar = .current) -> [Total] {
        var keys: Set<String> = []
        for offset in 0..<max(count, 1) {
            if let date = calendar.date(byAdding: .day, value: -offset, to: now) { keys.insert(Self.dayKey(date, calendar: calendar)) }
        }
        var sums: [String: Total] = [:]
        for (day, apps) in days where keys.contains(day) {
            for (key, usage) in apps {
                let old = sums[key]
                sums[key] = Total(id: key, name: usage.name, iconPath: usage.iconPath ?? old?.iconPath,
                                  received: (old?.received ?? 0) + usage.received, sent: (old?.sent ?? 0) + usage.sent)
            }
        }
        return sums.values.sorted { $0.total > $1.total }
    }

    func save() {
        guard dirty else { return }
        dirty = false
        lastSave = Date()
        if let data = try? JSONEncoder().encode(days) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func reset() {
        days = [:]
        dirty = true
        save()
    }
}
