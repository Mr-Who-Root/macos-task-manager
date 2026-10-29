import Foundation

enum ProcKind: Int, CaseIterable, Sendable {
    case app, background, system

    var title: String {
        switch self {
        case .app: return "Apps"
        case .background: return "Background processes"
        case .system: return "macOS processes"
        }
    }

    var historyTag: String {
        switch self {
        case .app: return "app"
        case .background: return "background"
        case .system: return "system"
        }
    }
}

/// A running application as seen by NSWorkspace, captured on the main thread.
struct AppRef: Sendable {
    let pid: Int32
    let bundlePath: String?
    let name: String
    let isRegular: Bool
}

enum EfficiencyState: Sendable { case off, partial, on }

/// One top-level row on the Processes tab: an app with its helpers, or a single process.
struct ProcNode: Identifiable, Sendable {
    let id: String
    let kind: ProcKind
    let name: String
    let iconPath: String?
    let bundlePath: String?
    let mainPID: Int32
    let isApp: Bool
    let historyKey: String
    var members: [ProcessSample]

    var cpu: Double = 0
    var memory: UInt64 = 0
    var diskRate: Double = 0
    var netRate: Double = 0
    var power: Double = 0
    var powerTrend: Double = 0
    var cpuTrend: Double = 0
    var idleWakeups: Double = 0
    var threads: Int = 0
    var cpuDelta: Double = 0
    var diskDelta: Double = 0
    var netDelta: Double = 0
    var netReceivedDelta: Double = 0
    var netSentDelta: Double = 0
    var energyDelta: Double = 0

    var main: ProcessSample? { members.first { $0.pid == mainPID } ?? members.first }
    var uid: UInt32 { main?.uid ?? 0 }
    var path: String? { bundlePath ?? main?.path }
    var pids: [Int32] { members.map(\.pid) }
    var isSuspended: Bool { !members.isEmpty && members.allSatisfy(\.isSuspended) }
    var notResponding: Bool { members.contains(where: \.notResponding) }

    var efficiency: EfficiencyState {
        let count = members.filter(\.efficiencyMode).count
        if count == 0 { return .off }
        return (main?.efficiencyMode ?? false) || count == members.count ? .on : .partial
    }

    var statusText: String {
        if notResponding { return "Not responding" }
        if isSuspended { return "Suspended" }
        switch efficiency {
        case .on:
            let count = members.filter(\.efficiencyMode).count
            return count == members.count || members.count == 1 ? "Efficiency mode" : "Efficiency mode (\(count) of \(members.count))"
        case .partial:
            return "Efficiency mode (\(members.filter(\.efficiencyMode).count) of \(members.count))"
        case .off:
            return members.count == 1 ? (main?.statusText ?? "") : ""
        }
    }

    mutating func recalculate() {
        cpu = 0; memory = 0; diskRate = 0; netRate = 0; threads = 0
        power = 0; powerTrend = 0; cpuTrend = 0; idleWakeups = 0
        cpuDelta = 0; diskDelta = 0; netDelta = 0; netReceivedDelta = 0; netSentDelta = 0; energyDelta = 0
        for m in members {
            cpu += m.cpu
            memory += m.memory
            diskRate += m.diskRate
            netRate += m.netRate
            power += m.power
            powerTrend += m.powerTrend
            cpuTrend += m.cpuTrend
            idleWakeups += m.idleWakeups
            threads += m.threads
            cpuDelta += m.cpuDelta
            diskDelta += m.diskDelta
            netDelta += m.netDelta
            netReceivedDelta += m.netReceivedDelta
            netSentDelta += m.netSentDelta
            energyDelta += m.energyDelta
        }
        cpu = min(cpu, 100)
    }
}

enum ProcessTreeBuilder {
    /// Groups processes the way Windows does: apps (with all of their helper processes),
    /// background processes, and operating system processes.
    static func build(_ processes: [ProcessSample], apps: [AppRef], currentUID: UInt32) -> [ProcNode] {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        var children: [Int32: [Int32]] = [:]
        for p in processes where p.pid != p.ppid {
            children[p.ppid, default: []].append(p.pid)
        }
        var bundleOf: [Int32: String] = [:]
        var byBundle: [String: [Int32]] = [:]
        for p in processes {
            if let bundle = BundlePaths.outermostApp(p.path) {
                bundleOf[p.pid] = bundle
                byBundle[bundle, default: []].append(p.pid)
            }
        }

        var assigned: Set<Int32> = []
        var nodes: [ProcNode] = []

        // 1. Apps known to NSWorkspace. Regular apps first so they claim their helpers.
        let runningApps = apps.filter { byPID[$0.pid] != nil }.sorted { ($0.isRegular ? 0 : 1, $0.pid) < ($1.isRegular ? 0 : 1, $1.pid) }
        let regularBundles = Set(runningApps.filter(\.isRegular).compactMap(\.bundlePath))
        let appPIDs = Set(runningApps.map(\.pid))
        for app in runningApps where !assigned.contains(app.pid) {
            var memberPIDs: [Int32] = [app.pid]
            assigned.insert(app.pid)
            if let bundle = app.bundlePath {
                for pid in byBundle[bundle] ?? [] where !assigned.contains(pid) {
                    memberPIDs.append(pid)
                    assigned.insert(pid)
                }
            }
            // Child processes (e.g. shells started by a terminal) belong to the app too,
            // unless they are part of another app's bundle.
            var queue = [app.pid]
            while let pid = queue.popLast() {
                for child in children[pid] ?? [] where !assigned.contains(child) && !appPIDs.contains(child) {
                    if let childBundle = bundleOf[child], childBundle != app.bundlePath, regularBundles.contains(childBundle) { continue }
                    memberPIDs.append(child)
                    assigned.insert(child)
                    queue.append(child)
                }
            }
            let main = byPID[app.pid]!
            let kind: ProcKind = app.isRegular ? .app : (BundlePaths.isSystem(app.bundlePath ?? main.path) ? .system : .background)
            let name = app.name.isEmpty ? (app.bundlePath.map(BundlePaths.displayName) ?? main.name) : app.name
            var node = ProcNode(
                id: "app:\(app.bundlePath ?? main.name):\(app.pid)",
                kind: kind,
                name: name,
                iconPath: app.bundlePath ?? main.path,
                bundlePath: app.bundlePath,
                mainPID: app.pid,
                isApp: true,
                historyKey: app.bundlePath ?? "exe:\(main.path ?? main.name)",
                members: memberPIDs.compactMap { byPID[$0] }
            )
            node.recalculate()
            nodes.append(node)
        }

        // 2. Remaining processes that live inside an .app bundle are grouped by that bundle.
        for (bundle, pids) in byBundle {
            let remaining = pids.filter { !assigned.contains($0) }.sorted()
            guard let first = remaining.first else { continue }
            remaining.forEach { assigned.insert($0) }
            let members = remaining.compactMap { byPID[$0] }
            let main = members.first { $0.path.flatMap(BundlePaths.innermostApp) == bundle } ?? byPID[first]!
            var node = ProcNode(
                id: "bundle:\(bundle)",
                kind: BundlePaths.isSystem(bundle) ? .system : .background,
                name: members.count == 1 ? main.name : BundlePaths.displayName(bundle),
                iconPath: bundle,
                bundlePath: members.count == 1 ? nil : bundle,
                mainPID: main.pid,
                isApp: false,
                historyKey: bundle,
                members: members
            )
            node.recalculate()
            nodes.append(node)
        }

        // 3. Everything else is shown as an individual process.
        for p in processes where !assigned.contains(p.pid) {
            var node = ProcNode(
                id: "pid:\(p.pid)",
                kind: BundlePaths.isSystem(p.path) ? .system : .background,
                name: p.name,
                iconPath: p.path,
                bundlePath: nil,
                mainPID: p.pid,
                isApp: false,
                historyKey: "exe:\(p.path ?? p.name)",
                members: [p]
            )
            node.recalculate()
            nodes.append(node)
        }
        return nodes
    }
}
