import SwiftUI

/// Converts process nodes into table rows, with sorting and search filtering.
@MainActor
enum ProcessRows {
    static func row(for node: ProcNode, expanded: Bool) -> HeatRow {
        let main = node.main
        let grouped = node.members.count > 1
        return HeatRow(
            id: node.id,
            style: .parent,
            title: node.name,
            count: node.members.count,
            iconPath: node.iconPath,
            symbol: node.iconPath == nil ? "cpu" : nil,
            isExpandable: grouped,
            isExpanded: grouped && expanded,
            statusText: node.statusText,
            efficiency: node.efficiency,
            suspended: node.isSuspended,
            cpu: node.cpu,
            memory: node.memory,
            disk: node.diskRate,
            network: node.netRate,
            pid: grouped ? nil : node.mainPID,
            processName: main?.name ?? "",
            publisher: CodeSigning.cachedPublisher(node.path) ?? "",
            user: main?.user ?? "",
            threads: node.threads,
            architecture: main?.architecture ?? "",
            target: RowTarget(node: node)
        )
    }

    static func row(for process: ProcessSample, in node: ProcNode) -> HeatRow {
        HeatRow(
            id: "\(node.id)/\(process.pid)",
            style: .child,
            title: process.name,
            iconPath: BundlePaths.innermostApp(process.path) ?? process.path,
            statusText: process.statusText,
            efficiency: process.efficiencyMode ? .on : .off,
            suspended: process.isSuspended,
            cpu: process.cpu,
            memory: process.memory,
            disk: process.diskRate,
            network: process.netRate,
            pid: process.pid,
            processName: process.name,
            publisher: CodeSigning.cachedPublisher(process.path) ?? "",
            user: process.user,
            threads: process.threads,
            architecture: process.architecture,
            target: RowTarget(process: process, kind: node.kind, isApp: node.isApp && process.pid == node.mainPID)
        )
    }

    static func matches(_ query: String, node: ProcNode) -> Bool {
        matches(query, name: node.name, path: node.path, pid: node.members.count == 1 ? node.mainPID : nil)
    }

    static func matches(_ query: String, process: ProcessSample) -> Bool {
        matches(query, name: process.name, path: process.path, pid: process.pid)
    }

    private static func matches(_ query: String, name: String, path: String?, pid: Int32?) -> Bool {
        if name.localizedCaseInsensitiveContains(query) { return true }
        if let pid, String(pid).hasPrefix(query) { return true }
        if let publisher = CodeSigning.cachedPublisher(path), publisher.localizedCaseInsensitiveContains(query) { return true }
        return false
    }

    static func sorted(_ nodes: [ProcNode], by sort: TableSort) -> [ProcNode] {
        nodes.sorted { a, b in
            let order = compare(a, b, sort.column)
            if order == .orderedSame { return a.name.localizedStandardCompare(b.name) == .orderedAscending }
            return sort.ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }

    static func sorted(_ processes: [ProcessSample], by sort: TableSort) -> [ProcessSample] {
        processes.sorted { a, b in
            let order = compare(a, b, sort.column)
            if order == .orderedSame { return a.pid < b.pid }
            return sort.ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }

    private static func compare(_ a: ProcNode, _ b: ProcNode, _ column: ProcColumn) -> ComparisonResult {
        switch column {
        case .name: return a.name.localizedStandardCompare(b.name)
        case .status: return a.statusText.localizedStandardCompare(b.statusText)
        case .publisher: return (CodeSigning.cachedPublisher(a.path) ?? "").localizedStandardCompare(CodeSigning.cachedPublisher(b.path) ?? "")
        case .pid: return value(a.mainPID, b.mainPID)
        case .processName: return (a.main?.name ?? "").localizedStandardCompare(b.main?.name ?? "")
        case .user: return (a.main?.user ?? "").localizedStandardCompare(b.main?.user ?? "")
        case .threads: return value(a.threads, b.threads)
        case .architecture: return (a.main?.architecture ?? "").compare(b.main?.architecture ?? "")
        case .cpu: return value(a.cpu, b.cpu)
        case .memory: return value(a.memory, b.memory)
        case .disk: return value(a.diskRate, b.diskRate)
        case .network: return value(a.netRate, b.netRate)
        }
    }

    private static func compare(_ a: ProcessSample, _ b: ProcessSample, _ column: ProcColumn) -> ComparisonResult {
        switch column {
        case .name, .processName: return a.name.localizedStandardCompare(b.name)
        case .status: return a.statusText.localizedStandardCompare(b.statusText)
        case .publisher: return (CodeSigning.cachedPublisher(a.path) ?? "").localizedStandardCompare(CodeSigning.cachedPublisher(b.path) ?? "")
        case .pid: return value(a.pid, b.pid)
        case .user: return a.user.localizedStandardCompare(b.user)
        case .threads: return value(a.threads, b.threads)
        case .architecture: return a.architecture.compare(b.architecture)
        case .cpu: return value(a.cpu, b.cpu)
        case .memory: return value(a.memory, b.memory)
        case .disk: return value(a.diskRate, b.diskRate)
        case .network: return value(a.netRate, b.netRate)
        }
    }

    private static func value<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }

    static func totals(_ monitor: Monitor) -> HeaderTotals {
        HeaderTotals(
            cpu: monitor.system.cpu.total,
            memory: monitor.system.memory.usedFraction,
            disk: monitor.diskActiveFraction,
            network: monitor.networkFraction
        )
    }
}

/// Right-click menu shared by the Processes and Users tabs.
struct ProcessRowMenu: View {
    let row: HeatRow
    let toggle: (String) -> Void
    @Environment(AppState.self) private var state

    var body: some View {
        if row.isExpandable {
            Button(row.isExpanded ? "Collapse" : "Expand") { toggle(row.id) }
            Divider()
        }
        if let target = row.target {
            if target.isFinder {
                Button("Restart") { ProcessActions.restartFinder() }
            } else {
                Button("End task") { ProcessActions.requestEndTask(target) }
                Button("Force end task") { ProcessActions.requestEndTask(target, force: true) }
            }
            Toggle("Efficiency mode", isOn: Binding(
                get: { target.efficiency },
                set: { ProcessActions.setEfficiency(target, enabled: $0) }
            ))
            Button(target.suspended ? "Resume" : "Suspend") {
                ProcessActions.setSuspended(target, suspended: !target.suspended)
            }
            Divider()
            Button("Go to details") { state.showDetails(for: target.mainPID) }
            Button("Open file location") { ProcessActions.revealInFinder(target.path) }
                .disabled(target.path == nil)
            Button("Search online") { ProcessActions.searchOnline(target.name) }
            Button("Properties") { state.properties = PropertiesTarget(pid: target.mainPID) }
            Divider()
            Button("Copy name") { ProcessActions.copy(target.name) }
            Button("Copy PID") { ProcessActions.copy(target.pids.map(String.init).joined(separator: ", ")) }
        }
    }
}
