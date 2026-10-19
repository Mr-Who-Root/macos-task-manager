import SwiftUI

extension ServiceEntry {
    var domainName: String { domain.rawValue }
}

struct ServicesPage: View {
    @Environment(AppState.self) private var state
    @State private var services: [ServiceEntry] = []
    @State private var loaded = false
    @State private var sortOrder = [KeyPathComparator(\ServiceEntry.label, comparator: .localizedStandard)]
    @State private var selection: ServiceEntry.ID?

    var body: some View {
        let items = filtered.sorted(using: sortOrder)
        let selected = items.first { $0.id == selection }
        VStack(spacing: 0) {
            PageHeader(title: "Services") {
                if loaded {
                    Text("\(services.filter(\.isRunning).count) running · \(services.count) total")
                        .font(.system(size: 12))
                        .foregroundStyle(Fluent.textSecondary)
                        .padding(.trailing, 8)
                }
                CommandButton(title: "Run new task", systemImage: "macwindow.badge.plus") { state.showRunTask = true }
                CommandSeparator()
                CommandButton(title: "Start", systemImage: "play", isDisabled: selected == nil || selected?.isRunning == true) {
                    if let selected { perform(.start, selected) }
                }
                CommandButton(title: "Stop", systemImage: "stop", isDisabled: selected?.isRunning != true) {
                    if let selected { perform(.stop, selected) }
                }
                CommandButton(title: "Restart", systemImage: "arrow.clockwise", isDisabled: selected == nil) {
                    if let selected { perform(.restart, selected) }
                }
            }
            Table(items, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.label) { Text($0.label) }
                    .width(min: 200, ideal: 330)
                TableColumn("PID", value: \.pidSortKey) { s in
                    Text(s.pidText).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 44, ideal: 60)
                TableColumn("Description", value: \.program) { s in
                    Text(s.program).foregroundStyle(Fluent.textSecondary).truncationMode(.middle)
                }
                .width(min: 120, ideal: 320)
                TableColumn("Status", value: \.status) { s in
                    Text(s.status).foregroundStyle(s.isRunning ? Fluent.textPrimary : Fluent.textSecondary)
                }
                .width(min: 60, ideal: 76)
                TableColumn("Group", value: \.domainName) { Text($0.domainName) }
                    .width(min: 50, ideal: 70)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: ServiceEntry.ID.self) { ids in
                if let id = ids.first, let service = services.first(where: { $0.id == id }) {
                    Button("Start") { perform(.start, service) }.disabled(service.isRunning)
                    Button("Stop") { perform(.stop, service) }.disabled(!service.isRunning)
                    Button("Restart") { perform(.restart, service) }
                    Divider()
                    if let pid = service.pid {
                        Button("Go to details") { state.showDetails(for: pid) }
                    }
                    Button("Open file location") { ProcessActions.revealInFinder(service.plistPath) }
                        .disabled(service.plistPath == nil)
                    Button("Search online") { ProcessActions.searchOnline(service.label) }
                    Divider()
                    Button("Copy name") { ProcessActions.copy(service.label) }
                }
            }
            .overlay {
                if !loaded { ProgressView().controlSize(.small) }
            }
        }
        .task {
            while !Task.isCancelled {
                await reload()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private var filtered: [ServiceEntry] {
        let query = state.searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return services }
        return services.filter {
            $0.label.localizedCaseInsensitiveContains(query) || $0.program.localizedCaseInsensitiveContains(query) || $0.pidText.hasPrefix(query)
        }
    }

    private func reload() async {
        services = await Task.detached { Launchd.services() }.value
        loaded = true
    }

    private func perform(_ action: Launchd.ServiceAction, _ service: ServiceEntry) {
        Task {
            let result = await Task.detached { Launchd.perform(action, on: service) }.value
            if !result.succeeded && !Shell.wasCancelled(result) {
                state.alert = AppAlert(
                    title: "Couldn't \(action == .start ? "start" : action == .stop ? "stop" : "restart") “\(service.label)”",
                    message: result.error.isEmpty ? "launchctl reported an error." : result.error
                )
            }
            try? await Task.sleep(for: .milliseconds(500))
            await reload()
        }
    }
}
