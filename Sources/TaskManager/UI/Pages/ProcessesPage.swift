import SwiftUI

struct ProcessesPage: View {
    @Environment(Monitor.self) private var monitor
    @Environment(AppState.self) private var state
    @Environment(AppSettings.self) private var settings
    @State private var expanded: Set<String> = []
    @State private var selection: String?
    @State private var sort = TableSort()

    var body: some View {
        let rows = buildRows()
        let target = rows.first { $0.id == selection }?.target
        VStack(spacing: 0) {
            PageHeader(title: "Processes") {
                CommandButton(title: "Run new task", systemImage: "macwindow.badge.plus") { state.showRunTask = true }
                CommandSeparator()
                CommandButton(title: "End task", systemImage: "nosign", isDisabled: target == nil) {
                    if let target { ProcessActions.requestEndTask(target) }
                }
                CommandButton(title: "Efficiency mode", systemImage: target?.efficiency == true ? "leaf.fill" : "leaf",
                              isDisabled: target == nil || target?.ownedByUser == false, isOn: target?.efficiency == true) {
                    if let target { ProcessActions.setEfficiency(target, enabled: !target.efficiency) }
                }
                CommandBarMenu(title: "View", systemImage: "rectangle.3.group") {
                    Toggle("Group by type", isOn: Binding(get: { settings.groupByType }, set: { settings.groupByType = $0 }))
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
        .onChange(of: state.endTaskRequest) { endSelected() }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private func endSelected() {
        guard state.page == .processes, let target = buildRows().first(where: { $0.id == selection })?.target else { return }
        ProcessActions.requestEndTask(target)
    }

    private func buildRows() -> [HeatRow] {
        _ = monitor.publisherRevision
        let query = state.searchText.trimmingCharacters(in: .whitespaces)
        var visible: [(node: ProcNode, members: [ProcessSample], forceExpand: Bool)] = []
        for node in monitor.nodes {
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
