import Darwin
import SwiftUI

struct UsersPage: View {
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
            PageHeader(title: "Users") {
                CommandButton(title: "Run new task", systemImage: "macwindow.badge.plus") { state.showRunTask = true }
                CommandSeparator()
                CommandButton(title: "End task", systemImage: "nosign", isDisabled: target == nil) {
                    if let target { ProcessActions.requestEndTask(target) }
                }
                CommandBarMenu(title: "View", systemImage: "rectangle.3.group") {
                    Toggle("Show full account name", isOn: Binding(get: { settings.showFullAccountName }, set: { settings.showFullAccountName = $0 }))
                    Divider()
                    Button("Expand all") { expanded = Set(rows.filter { $0.style == .parent }.map(\.id)) }
                    Button("Collapse all") { expanded = [] }
                }
            }
            HeatTable(
                rows: rows,
                columns: [.name, .status, .cpu, .memory, .disk, .network],
                nameTitle: "User",
                totals: ProcessRows.totals(monitor),
                sort: $sort,
                selection: $selection,
                memoryTotal: monitor.system.memory.total,
                configurableColumns: false,
                onToggle: toggle,
                onDelete: {
                    if let target { ProcessActions.requestEndTask(target) }
                }
            ) { row in
                ProcessRowMenu(row: row, toggle: toggle)
            }
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    /// Signed-in (human) accounts, each expandable to the apps and processes it runs.
    private func buildRows() -> [HeatRow] {
        let query = state.searchText.trimmingCharacters(in: .whitespaces)
        let byUser = Dictionary(grouping: monitor.nodes.filter { $0.uid >= 500 && $0.uid < 65_534 }, by: \.uid)
        var users: [(uid: UInt32, name: String, nodes: [ProcNode], total: ProcNode)] = []
        for (uid, nodes) in byUser {
            var total = ProcNode(id: "user:\(uid)", kind: .app, name: displayName(uid), iconPath: nil, bundlePath: nil,
                                 mainPID: 0, isApp: false, historyKey: "", members: nodes.flatMap(\.members))
            total.recalculate()
            users.append((uid, total.name, nodes, total))
        }

        var rows: [HeatRow] = []
        let sortedUsers = ProcessRows.sorted(users.map(\.total), by: sort)
        for total in sortedUsers {
            guard let user = users.first(where: { $0.total.id == total.id }) else { continue }
            let nodes = query.isEmpty ? user.nodes : user.nodes.filter { ProcessRows.matches(query, node: $0) }
            if !query.isEmpty && nodes.isEmpty && !user.name.localizedCaseInsensitiveContains(query) { continue }
            let isExpanded = expanded.contains(total.id) || !query.isEmpty
            rows.append(HeatRow(
                id: total.id, style: .parent, title: user.name, symbol: "person.crop.circle",
                isExpandable: true, isExpanded: isExpanded,
                statusText: "", cpu: total.cpu, memory: total.memory, disk: total.diskRate, network: total.netRate
            ))
            if isExpanded {
                for node in ProcessRows.sorted(nodes, by: sort) {
                    var row = ProcessRows.row(for: node, expanded: false)
                    row.style = .child
                    row.isExpandable = false
                    rows.append(row)
                }
            }
        }
        return rows
    }

    private func displayName(_ uid: UInt32) -> String {
        guard let entry = getpwuid(uid) else { return String(uid) }
        let short = String(cString: entry.pointee.pw_name)
        let full = String(cString: entry.pointee.pw_gecos)
        return settings.showFullAccountName && !full.isEmpty ? "\(full) (\(short))" : short
    }
}
