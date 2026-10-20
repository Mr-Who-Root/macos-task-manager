import Foundation
import Observation

/// Processes the user put in efficiency mode.
///
/// macOS can't tell us this directly: `getpriority(PRIO_DARWIN_PROCESS)` only reports the
/// calling process, and hundreds of processes already run at background priority because
/// macOS put them there. So Task Manager remembers what it changed (by PID and start time,
/// which survives PID reuse) and shows the leaf only while the process is still at
/// background priority.
@Observable @MainActor
final class EfficiencyStore {
    static let shared = EfficiencyStore()

    /// Base scheduling priority of a background (throttled) task.
    nonisolated static let backgroundPriority: Int32 = 4

    private static let defaultsKey = "efficiencyProcesses"
    private(set) var keys: Set<String>

    private init() {
        keys = Set(UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? [])
    }

    nonisolated static func key(pid: Int32, startTime: Date) -> String {
        "\(pid)@\(Int(startTime.timeIntervalSince1970 * 1000))"
    }

    func setEnabled(_ enabled: Bool, pids: [Int32]) {
        let monitor = Monitor.shared
        var updated = keys
        for pid in pids {
            guard let process = monitor.process(pid) else { continue }
            let key = Self.key(pid: pid, startTime: process.startTime)
            if enabled { updated.insert(key) } else { updated.remove(key) }
        }
        save(updated)
    }

    /// Forgets processes that exited, and ones whose priority was restored by the app or macOS.
    func reconcile(with processes: [ProcessSample]) {
        guard !keys.isEmpty else { return }
        let still = Set(processes.compactMap { process -> String? in
            let key = Self.key(pid: process.pid, startTime: process.startTime)
            guard keys.contains(key) else { return nil }
            // Unknown priority (0) keeps the entry rather than guessing.
            return process.basePriority == 0 || process.basePriority <= Self.backgroundPriority ? key : nil
        })
        if still != keys { save(still) }
    }

    private func save(_ updated: Set<String>) {
        guard updated != keys else { return }
        keys = updated
        UserDefaults.standard.set(Array(updated), forKey: Self.defaultsKey)
    }
}
