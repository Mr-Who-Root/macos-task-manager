import SwiftUI

struct AppHistoryPage: View {
    @Environment(Monitor.self) private var monitor
    @Environment(AppState.self) private var state
    @State private var mode = Mode.resources

    enum Mode: String, CaseIterable, Identifiable {
        case resources, data
        var id: String { rawValue }
        var title: String { self == .resources ? "Resource usage" : "Data usage" }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "App history") {
                Picker("Show", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(.trailing, 8)
                CommandButton(title: "Run new task", systemImage: "macwindow.badge.plus") { state.showRunTask = true }
                CommandSeparator()
                CommandButton(title: mode == .resources ? "Delete usage history" : "Delete data usage", systemImage: "trash") {
                    if mode == .resources {
                        state.alert = AppAlert(
                            title: "Delete usage history?",
                            message: "This clears the CPU time, network, disk and energy usage recorded for every app.",
                            action: .init(title: "Delete", role: .destructive) { monitor.appHistory.reset() }
                        )
                    } else {
                        state.alert = AppAlert(
                            title: "Delete data usage?",
                            message: "This clears the downloads and uploads recorded for every app.",
                            action: .init(title: "Delete", role: .destructive) { monitor.dataUsage.reset() }
                        )
                    }
                }
            }
            switch mode {
            case .resources: ResourceUsageTable()
            case .data: DataUsageView()
            }
        }
    }
}

/// CPU time, network, disk and energy per app since history began.
private struct ResourceUsageTable: View {
    @Environment(Monitor.self) private var monitor
    @Environment(AppState.self) private var state
    @Environment(AppSettings.self) private var settings
    @State private var sortOrder = [KeyPathComparator(\AppHistoryStore.Entry.cpuTime, order: .reverse)]
    @State private var selection: String?

    var body: some View {
        let history = monitor.appHistory
        let entries = filtered(Array(history.entries.values)).sorted(using: sortOrder)
        VStack(spacing: 0) {
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
                if monitor.energyAvailable {
                    TableColumn("Energy", value: \.energy) { entry in
                        Text(Fmt.energy(entry.energy)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .width(min: 70, ideal: 100)
                }
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
                    Text("Usage appears here as apps use CPU, disk, network and energy.")
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

/// Downloads and uploads per app, for today, the last week or the last month.
private struct DataUsageView: View {
    @Environment(Monitor.self) private var monitor
    @Environment(AppState.self) private var state
    @State private var period = Period.today
    @State private var sortOrder = [KeyPathComparator(\DataUsageStore.Total.total, order: .reverse)]
    @State private var selection: String?

    enum Period: Int, CaseIterable, Identifiable {
        case today = 1, week = 7, month = 30
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .today: return "Today"
            case .week: return "Last 7 days"
            case .month: return "Last 30 days"
            }
        }
    }

    /// Uploads above this in the period are highlighted.
    static let heavyUpload = 1_000_000_000.0

    var body: some View {
        let query = state.searchText.trimmingCharacters(in: .whitespaces)
        let all = monitor.dataUsage.totals(days: period.rawValue)
        let rows = all.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.sorted(using: sortOrder)
        let received = all.reduce(0) { $0 + $1.received }
        let sent = all.reduce(0) { $0 + $1.sent }
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Picker("Period", selection: $period) {
                    ForEach(Period.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Label(Fmt.bytes(received), systemImage: "arrow.down").monospacedDigit()
                Label(Fmt.bytes(sent), systemImage: "arrow.up").monospacedDigit()
                Text("Network data per app, recorded while Task Manager is running.")
                    .foregroundStyle(Fluent.textSecondary)
                    .lineLimit(1)
                Spacer()
            }
            .font(.system(size: 12))
            .padding(.horizontal, 22)
            .padding(.bottom, 8)

            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name) { row in
                    HStack(spacing: 6) {
                        ProcessIcon(path: row.iconPath).frame(width: 16, height: 16)
                        Text(row.name)
                    }
                }
                .width(min: 180, ideal: 320)
                TableColumn("Downloaded", value: \.received) { row in
                    Text(Fmt.bytes(row.received)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 80, ideal: 110)
                TableColumn("Uploaded", value: \.sent) { row in
                    HStack(spacing: 4) {
                        Spacer(minLength: 0)
                        if row.sent >= Self.heavyUpload {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(ChargeScale.low)
                                .help("Uploaded a lot in this period")
                        }
                        Text(Fmt.bytes(row.sent)).monospacedDigit()
                            .foregroundStyle(row.sent >= Self.heavyUpload ? ChargeScale.low : Fluent.textPrimary)
                    }
                }
                .width(min: 80, ideal: 110)
                TableColumn("Total", value: \.total) { row in
                    Text(Fmt.bytes(row.total)).monospacedDigit().fontWeight(.medium).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 80, ideal: 110)
                TableColumn("Share") { row in
                    let share = (received + sent) > 0 ? row.total / (received + sent) : 0
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Fluent.subtleSelected)
                            Capsule().fill(ResourceColor.network).frame(width: max(3, geometry.size.width * share))
                        }
                        .frame(height: 6)
                        .frame(maxHeight: .infinity)
                    }
                }
                .width(min: 80, ideal: 140)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            .foregroundStyle(Fluent.textPrimary)
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let row = rows.first(where: { $0.id == id }) {
                    Button("Search online") { ProcessActions.searchOnline(row.name) }
                    Button("Open file location") { ProcessActions.revealInFinder(row.iconPath) }
                        .disabled(row.iconPath == nil)
                    Divider()
                    Button("Copy name") { ProcessActions.copy(row.name) }
                }
            }
            .overlay {
                if rows.isEmpty {
                    Text("Downloads and uploads appear here as apps use the network.")
                        .foregroundStyle(Fluent.textSecondary)
                }
            }
        }
    }
}
