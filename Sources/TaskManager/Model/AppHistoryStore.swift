import Foundation
import Observation

/// Cumulative resource usage per app, recorded while Task Manager runs and saved to disk.
@Observable @MainActor
final class AppHistoryStore {
    struct Entry: Codable, Identifiable, Hashable {
        let id: String
        var name: String
        var iconPath: String?
        var kind: String
        var cpuTime: Double
        var networkBytes: Double
        var diskBytes: Double
        var energy: Double = 0      // joules
        var lastUsed: Date
    }

    private struct Archive: Codable {
        var since: Date
        var entries: [Entry]
    }

    private(set) var entries: [String: Entry] = [:]
    private(set) var since = Date()

    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var lastSave = Date()
    @ObservationIgnored private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        let directory = support.appendingPathComponent("TaskManager", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("AppHistory.json")
        if let data = try? Data(contentsOf: fileURL), let archive = try? JSONDecoder().decode(Archive.self, from: data) {
            since = archive.since
            entries = Dictionary(archive.entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        }
    }

    func record(_ nodes: [ProcNode]) {
        var updated = entries
        var changed = false
        let now = Date()
        for node in nodes where node.cpuDelta > 0 || node.netDelta > 0 || node.diskDelta > 0 || node.energyDelta > 0 {
            var entry = updated[node.historyKey] ?? Entry(
                id: node.historyKey, name: node.name, iconPath: node.iconPath, kind: node.kind.historyTag,
                cpuTime: 0, networkBytes: 0, diskBytes: 0, lastUsed: now
            )
            entry.name = node.name
            entry.kind = node.kind.historyTag
            entry.cpuTime += node.cpuDelta
            entry.networkBytes += node.netDelta
            entry.diskBytes += node.diskDelta
            entry.energy += node.energyDelta
            entry.lastUsed = now
            updated[node.historyKey] = entry
            changed = true
        }
        if changed {
            entries = updated
            dirty = true
        }
        if dirty && now.timeIntervalSince(lastSave) > 30 { save() }
    }

    func save() {
        guard dirty else { return }
        dirty = false
        lastSave = Date()
        let archive = Archive(since: since, entries: Array(entries.values))
        if let data = try? JSONEncoder().encode(archive) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func reset() {
        entries = [:]
        since = Date()
        dirty = true
        save()
    }
}

extension AppHistoryStore.Entry {
    /// History saved by earlier versions has no energy figure.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        iconPath = try c.decodeIfPresent(String.self, forKey: .iconPath)
        kind = try c.decode(String.self, forKey: .kind)
        cpuTime = try c.decode(Double.self, forKey: .cpuTime)
        networkBytes = try c.decode(Double.self, forKey: .networkBytes)
        diskBytes = try c.decode(Double.self, forKey: .diskBytes)
        energy = try c.decodeIfPresent(Double.self, forKey: .energy) ?? 0
        lastUsed = try c.decode(Date.self, forKey: .lastUsed)
    }
}
