import AppKit
import SwiftUI

extension StartupItem {
    var kindName: String { kind.rawValue }
}

struct StartupAppsPage: View {
    @Environment(AppState.self) private var state
    @State private var items: [StartupItem] = []
    @State private var loaded = false
    @State private var loginItemsUnavailable = false
    @State private var sortOrder = [KeyPathComparator(\StartupItem.name, comparator: .localizedStandard)]
    @State private var selection: StartupItem.ID?

    var body: some View {
        let visible = filtered.sorted(using: sortOrder)
        let selected = visible.first { $0.id == selection }
        VStack(spacing: 0) {
            PageHeader(title: "Startup apps") {
                Text("Last boot: \(HardwareInfo.shared.bootTime.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 12))
                    .foregroundStyle(Fluent.textSecondary)
                    .padding(.trailing, 8)
                CommandButton(title: "Run new task", systemImage: "macwindow.badge.plus") { state.showRunTask = true }
                CommandSeparator()
                CommandButton(title: "Enable", systemImage: "checkmark.circle", isDisabled: selected == nil || selected?.enabled == true) {
                    if let selected { setEnabled(true, selected) }
                }
                CommandButton(title: "Disable", systemImage: "nosign", isDisabled: selected?.enabled != true) {
                    if let selected { setEnabled(false, selected) }
                }
                CommandButton(title: "Open file location", systemImage: "folder", isDisabled: selected == nil) {
                    ProcessActions.revealInFinder(selected?.plistPath ?? selected?.programPath)
                }
            }
            if loginItemsUnavailable {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill").foregroundStyle(Fluent.accent)
                    Text("Login items are hidden. Allow Task Manager to control “System Events” in Privacy & Security › Automation, then try again.")
                        .font(.system(size: 12))
                    Spacer()
                    Button("Open Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(StandardButtonStyle())
                    Button("Try again") { Task { await load() } }
                        .buttonStyle(StandardButtonStyle())
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 6).fill(Fluent.card))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Fluent.cardStroke))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            Table(visible, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name) { item in
                    HStack(spacing: 6) {
                        ProcessIcon(path: item.iconPath).frame(width: 16, height: 16)
                        Text(item.name)
                    }
                }
                .width(min: 150, ideal: 220)
                TableColumn("Publisher", value: \.publisher) { Text($0.publisher) }
                    .width(min: 80, ideal: 150)
                TableColumn("Status", value: \.status) { item in
                    Text(item.status).foregroundStyle(item.enabled ? Fluent.textPrimary : Fluent.textSecondary)
                }
                .width(min: 60, ideal: 80)
                TableColumn("Type", value: \.kindName) { Text($0.kindName) }
                    .width(min: 70, ideal: 110)
                TableColumn("Starts", value: \.trigger) { Text($0.trigger) }
                    .width(min: 70, ideal: 110)
                TableColumn("Location", value: \.location) { item in
                    Text(item.location).foregroundStyle(Fluent.textSecondary).truncationMode(.middle)
                }
                .width(min: 120, ideal: 300)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            .foregroundStyle(Fluent.textPrimary)
            .contextMenu(forSelectionType: StartupItem.ID.self) { ids in
                if let id = ids.first, let item = items.first(where: { $0.id == id }) {
                    Button(item.enabled ? "Disable" : "Enable") { setEnabled(!item.enabled, item) }
                    Divider()
                    Button("Open file location") { ProcessActions.revealInFinder(item.plistPath ?? item.programPath) }
                    Button("Search online") { ProcessActions.searchOnline(item.name) }
                    Divider()
                    Button("Copy name") { ProcessActions.copy(item.name) }
                }
            }
            .overlay {
                if !loaded {
                    ProgressView().controlSize(.small)
                } else if items.isEmpty {
                    Text("There are no startup items to display.").foregroundStyle(Fluent.textSecondary)
                }
            }
        }
        .task { await load() }
    }

    private var filtered: [StartupItem] {
        let query = state.searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.publisher.localizedCaseInsensitiveContains(query) || ($0.label ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private func load() async {
        let disabled = UserDefaults.standard.array(forKey: Launchd.disabledLoginItemsKey) as? [[String]] ?? []
        let (launchd, login) = await Task.detached {
            (Launchd.launchdStartupItems(), Launchd.loginItems(disabled: disabled))
        }.value
        items = (login ?? []) + launchd
        loginItemsUnavailable = login == nil
        loaded = true
    }

    private func setEnabled(_ enabled: Bool, _ item: StartupItem) {
        Task {
            let error = await Task.detached { Launchd.setEnabled(enabled, item: item) }.value
            if let error, !error.isEmpty {
                state.alert = AppAlert(title: "Couldn't \(enabled ? "enable" : "disable") “\(item.name)”", message: error)
            }
            await load()
        }
    }
}
