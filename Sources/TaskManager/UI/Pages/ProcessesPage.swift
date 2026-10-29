import SwiftUI

struct ProcessesPage: View {
    @Environment(Monitor.self) private var monitor
    @Environment(AppState.self) private var state
    @Environment(AppSettings.self) private var settings
    @State private var expanded: Set<String> = []
    @State private var selection: String?
    @State private var sort = TableSort()
    @State private var onlyEfficient = false
    @AppStorage("processesShowMap") private var showMap = false
    @State private var waitingOn: Set<Int32> = []

    var body: some View {
        let efficientCount = monitor.nodes.filter { $0.efficiency != .off }.count
        let rows = buildRows()
        let target = rows.first { $0.id == selection }?.target ?? mapTarget(selection)
        let hung = monitor.nodes.first { $0.notResponding && !waitingOn.contains($0.mainPID) }
        VStack(spacing: 0) {
            PageHeader(title: "Processes") {
                if efficientCount > 0 || onlyEfficient {
                    EfficiencyBadge(count: efficientCount, isFiltering: onlyEfficient) { onlyEfficient.toggle() }
                        .padding(.trailing, 6)
                }
                CommandButton(title: "Why is my Mac slow?", systemImage: "stethoscope") { state.showDiagnosis = true }
                CommandButton(title: "Run new task", systemImage: "macwindow.badge.plus") { state.showRunTask = true }
                CommandSeparator()
                EndTaskCommand(target: target)
                CommandButton(title: "Efficiency mode", systemImage: target?.efficiency == true ? "leaf.fill" : "leaf",
                              isDisabled: target == nil || target?.ownedByUser == false, isOn: target?.efficiency == true) {
                    if let target { ProcessActions.requestEfficiency(target, enabled: !target.efficiency) }
                }
                CommandButton(title: "Map", systemImage: "square.grid.3x2", isOn: showMap) { showMap.toggle() }
                CommandBarMenu(title: "View", systemImage: "rectangle.3.group") {
                    Toggle("Show as map", isOn: $showMap)
                    Divider()
                    Toggle("Group by type", isOn: Binding(get: { settings.groupByType }, set: { settings.groupByType = $0 }))
                    Toggle("Only processes in efficiency mode", isOn: $onlyEfficient)
                    Divider()
                    Button("Expand all") { expanded = Set(monitor.nodes.filter { $0.members.count > 1 }.map(\.id)) }
                    Button("Collapse all") { expanded = [] }
                    Divider()
                    Menu("Columns") {
                        ForEach(ProcColumn.allCases.filter(\.isOptional)) { column in
                            Toggle(column.title, isOn: Binding(
                                get: { settings.visibleColumns.contains(column) },
                                set: { _ in settings.toggleColumn(column) }
                            ))
                        }
                    }
                    Divider()
                    Button("Refresh now") { monitor.refreshNow() }
                }
            }
            if let hung {
                HangBanner(node: hung, sample: hung.pids.lazy.compactMap { monitor.hangSamples[$0] }.first) {
                    waitingOn.insert(hung.mainPID)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 10)
            }
            if showMap {
                ProcessMap(nodes: mapNodes(), selection: $selection)
            } else {
                HeatTable(
                    rows: rows,
                    columns: ProcColumn.allCases.filter { settings.visibleColumns.contains($0) },
                    totals: ProcessRows.totals(monitor),
                    sort: $sort,
                    selection: $selection,
                    memoryTotal: monitor.system.memory.total,
                    onToggle: toggle,
                    onActivate: { row in
                        if let pid = row.target?.mainPID { state.properties = PropertiesTarget(pid: pid) }
                    },
                    onDelete: endSelected
                ) { row in
                    ProcessRowMenu(row: row, toggle: toggle)
                }
            }
        }
        .onChange(of: monitor.nodes.filter(\.notResponding).map(\.mainPID)) { _, hung in
            // Ask again if an app hangs again after recovering.
            waitingOn.formIntersection(hung)
        }
        .onChange(of: state.endTaskRequest) { endSelected() }
        .onChange(of: efficientCount) { _, count in
            if count == 0 { onlyEfficient = false }
        }
        .onChange(of: monitor.tick) {
            if let name = DebugHooks.selectName, selection == nil, let row = buildRows().first(where: { $0.title == name }) {
                selection = row.id
            }
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private func endSelected() {
        guard state.page == .processes,
              let target = buildRows().first(where: { $0.id == selection })?.target ?? mapTarget(selection) else { return }
        ProcessActions.requestEndTask(target)
    }

    /// The app or process selected on the map (helper processes there aren't table rows).
    private func mapTarget(_ id: String?) -> RowTarget? {
        guard showMap, let id else { return nil }
        if let node = monitor.nodes.first(where: { $0.id == id }) { return RowTarget(node: node) }
        guard let slash = id.lastIndex(of: "/"), let pid = Int32(id[id.index(after: slash)...]),
              let node = monitor.nodes.first(where: { $0.id == id[..<slash] }),
              let process = node.members.first(where: { $0.pid == pid }) else { return nil }
        return RowTarget(process: process, kind: node.kind, isApp: node.isApp && pid == node.mainPID)
    }

    /// The map honours the search box and the efficiency filter, like the table.
    private func mapNodes() -> [ProcNode] {
        let query = state.searchText.trimmingCharacters(in: .whitespaces)
        return monitor.nodes.filter { node in
            (!onlyEfficient || node.efficiency != .off)
                && (query.isEmpty || ProcessRows.matches(query, node: node) || node.members.contains { ProcessRows.matches(query, process: $0) })
        }
    }

    private func buildRows() -> [HeatRow] {
        _ = monitor.publisherRevision
        let query = state.searchText.trimmingCharacters(in: .whitespaces)
        var visible: [(node: ProcNode, members: [ProcessSample], forceExpand: Bool)] = []
        for node in monitor.nodes where !onlyEfficient || node.efficiency != .off {
            if query.isEmpty || ProcessRows.matches(query, node: node) {
                visible.append((node, node.members, false))
            } else {
                let members = node.members.filter { ProcessRows.matches(query, process: $0) }
                if !members.isEmpty { visible.append((node, members, true)) }
            }
        }

        let lookup = Dictionary(visible.map { ($0.node.id, $0) }, uniquingKeysWith: { a, _ in a })
        var rows: [HeatRow] = []
        func emit(_ nodes: [ProcNode]) {
            for node in ProcessRows.sorted(nodes, by: sort) {
                guard let entry = lookup[node.id] else { continue }
                let isExpanded = expanded.contains(node.id) || entry.forceExpand
                rows.append(ProcessRows.row(for: node, expanded: isExpanded))
                if isExpanded && node.members.count > 1 {
                    for process in ProcessRows.sorted(entry.members, by: sort) {
                        rows.append(ProcessRows.row(for: process, in: node))
                    }
                }
            }
        }

        let nodes = visible.map(\.node)
        if settings.groupByType {
            for kind in ProcKind.allCases {
                let group = nodes.filter { $0.kind == kind }
                guard !group.isEmpty else { continue }
                rows.append(HeatRow(id: "section:\(kind.rawValue)", style: .section, title: kind.title, count: group.count))
                emit(group)
            }
        } else {
            emit(nodes)
        }
        return rows
    }
}

/// "Safari is not responding": End task, look at the sample, or wait.
private struct HangBanner: View {
    let node: ProcNode
    let sample: String?
    let wait: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 18))
                .foregroundStyle(ResourceColor.thermal)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(node.name) is not responding")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Fluent.textPrimary)
                Text("You can wait to see if it recovers, or end it. Unsaved work in it may be lost.")
                    .font(.system(size: 12))
                    .foregroundStyle(Fluent.textSecondary)
            }
            Spacer(minLength: 8)
            if let sample {
                Button("Show sample") { NSWorkspace.shared.open(URL(fileURLWithPath: sample)) }
                    .buttonStyle(StandardButtonStyle())
                    .help("What it was doing when it stopped responding, captured by Task Manager")
            }
            Button("Wait", action: wait)
                .buttonStyle(StandardButtonStyle())
            Button("End task") { ProcessActions.requestEndTask(RowTarget(node: node)) }
                .buttonStyle(AccentButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).fill(ResourceColor.thermal.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).strokeBorder(ResourceColor.thermal.opacity(0.45)))
    }
}

/// "🍃 3 in efficiency mode": shows at a glance what's throttled, and filters to it.
private struct EfficiencyBadge: View {
    let count: Int
    let isFiltering: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "leaf.fill")
                Text(count == 1 ? "1 in efficiency mode" : "\(count) in efficiency mode")
                if isFiltering {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Fluent.efficiency)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(Fluent.efficiency.opacity(isFiltering ? 0.22 : (hovering ? 0.16 : 0.1))))
            .overlay(Capsule().strokeBorder(Fluent.efficiency.opacity(isFiltering ? 0.6 : 0.3)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isFiltering ? "Show all processes" : "Show only the processes in efficiency mode")
    }
}
