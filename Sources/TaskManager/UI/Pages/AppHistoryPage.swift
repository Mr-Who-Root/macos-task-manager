import SwiftUI

struct AppHistoryPage: View {
    @Environment(Monitor.self) private var monitor
    @Environment(AppState.self) private var state
    @Environment(AppSettings.self) private var settings
    @State private var sortOrder = [KeyPathComparator(\AppHistoryStore.Entry.cpuTime, order: .reverse)]
    @State private var selection: String?

    var body: some View {
        let history = monitor.appHistory
        let entries = filtered(Array(history.entries.values)).sorted(using: sortOrder)
        VStack(spacing: 0) {
            PageHeader(title: "App history") {
                CommandButton(title: "Run new task", systemImage: "macwindow.badge.plus") { state.showRunTask = true }
                CommandSeparator()
                CommandButton(title: "Delete usage history", systemImage: "trash") {
                    state.alert = AppAlert(
                        title: "Delete usage history?",
                        message: "This clears the CPU time, network and disk usage recorded for every app.",
                        action: .init(title: "Delete", role: .destructive) { history.reset() }
                    )
                }
            }
            HStack {
                Text("Resource usage since \(history.since.formatted(date: .numeric, time: .omitted)) for the current user account, recorded while Task Manager is running.")
                    .font(.system(size: 12))
                    .foregroundStyle(Fluent.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 6)

            Table(entries, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name) { entry in
                    HStack(spacing: 6) {
                        ProcessIcon(path: entry.iconPath).frame(width: 16, height: 16)
                        Text(entry.name)
                    }
                }
                .width(min: 180, ideal: 300)
                TableColumn("CPU time", value: \.cpuTime) { entry in
                    Text(Fmt.cpuTime(entry.cpuTime)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 70, ideal: 100)
                TableColumn("Network", value: \.networkBytes) { entry in
                    Text(Fmt.bytes(entry.networkBytes)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 70, ideal: 100)
                TableColumn("Disk", value: \.diskBytes) { entry in
                    Text(Fmt.bytes(entry.diskBytes)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 70, ideal: 100)
                TableColumn("Last active", value: \.lastUsed) { entry in
                    Text(entry.lastUsed.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(Fluent.textSecondary)
                }
                .width(min: 100, ideal: 160)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            .foregroundStyle(Fluent.textPrimary)
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let entry = history.entries[id] {
                    Button("Search online") { ProcessActions.searchOnline(entry.name) }
                    Button("Open file location") { ProcessActions.revealInFinder(entry.iconPath) }
                        .disabled(entry.iconPath == nil)
                    Divider()
                    Button("Copy name") { ProcessActions.copy(entry.name) }
                }
            }
            .overlay {
                if entries.isEmpty {
                    Text("Usage appears here as apps use CPU, disk and network.")
                        .foregroundStyle(Fluent.textSecondary)
                }
            }
        }
    }

    private func filtered(_ entries: [AppHistoryStore.Entry]) -> [AppHistoryStore.Entry] {
        let query = state.searchText.trimmingCharacters(in: .whitespaces)
        return entries.filter { entry in
            (settings.historyAllProcesses || entry.kind == ProcKind.app.historyTag)
                && (query.isEmpty || entry.name.localizedCaseInsensitiveContains(query))
        }
    }
}
