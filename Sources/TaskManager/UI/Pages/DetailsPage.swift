import AppKit
import SwiftUI

extension ProcessSample {
    var pathText: String { path ?? "" }
    var iconPath: String? { BundlePaths.innermostApp(path) ?? path }
}

struct DetailsPage: View {
    @Environment(Monitor.self) private var monitor
    @Environment(AppState.self) private var state
    @State private var sortOrder = [KeyPathComparator(\ProcessSample.name, comparator: .localizedStandard)]
    @State private var selection: Int32?

    private static let priorities: [(String, Int32)] = [
        ("High", -10), ("Above normal", -5), ("Normal", 0), ("Below normal", 5), ("Low", 10),
    ]

    var body: some View {
        let items = filtered.sorted(using: sortOrder)
        let selected = selection.flatMap { pid in items.first { $0.pid == pid } }
        VStack(spacing: 0) {
            PageHeader(title: "Details") {
                CommandButton(title: "Run new task", systemImage: "macwindow.badge.plus") { state.showRunTask = true }
                CommandSeparator()
                CommandButton(title: "End task", systemImage: "nosign", isDisabled: selected == nil) {
                    if let selected { ProcessActions.requestEndTask(target(for: selected)) }
                }
                CommandButton(title: "Efficiency mode", systemImage: selected?.efficiencyMode == true ? "leaf.fill" : "leaf",
                              isDisabled: selected == nil || selected?.restricted == true, isOn: selected?.efficiencyMode == true) {
                    if let selected { ProcessActions.setEfficiency(target(for: selected), enabled: !selected.efficiencyMode) }
                }
            }
            ScrollViewReader { proxy in
                Table(items, selection: $selection, sortOrder: $sortOrder) {
                    identityColumns
                    resourceColumns
                }
                .tableStyle(.inset(alternatesRowBackgrounds: false))
                .scrollContentBackground(.hidden)
                .contextMenu(forSelectionType: Int32.self) { pids in
                    if let pid = pids.first, let process = monitor.process(pid) {
                        menu(for: process)
                    }
                } primaryAction: { pids in
                    if let pid = pids.first { state.properties = PropertiesTarget(pid: pid) }
                }
                .onDeleteCommand {
                    if let selected { ProcessActions.requestEndTask(target(for: selected)) }
                }
                .onAppear { focusRequestedProcess(proxy) }
                .onChange(of: state.detailsFocusPID) { focusRequestedProcess(proxy) }
                .onChange(of: state.endTaskRequest) {
                    if let selected { ProcessActions.requestEndTask(target(for: selected)) }
                }
            }
        }
    }

    private typealias Comparator = KeyPathComparator<ProcessSample>

    @TableColumnBuilder<ProcessSample, Comparator>
    private var identityColumns: some TableColumnContent<ProcessSample, Comparator> {
        TableColumn("Name", value: \.name) { (p: ProcessSample) in
            HStack(spacing: 6) {
                ProcessIcon(path: p.iconPath).frame(width: 16, height: 16)
                Text(p.name)
            }
        }
        .width(min: 150, ideal: 210)
        TableColumn("PID", value: \.pid) { (p: ProcessSample) in
            Text(String(p.pid)).monospacedDigit()
        }
        .width(min: 44, ideal: 60)
        TableColumn("Status", value: \.detailStatus) { (p: ProcessSample) in
            Text(p.detailStatus)
        }
        .width(min: 60, ideal: 80)
        TableColumn("User name", value: \.user) { (p: ProcessSample) in
            Text(p.user)
        }
        .width(min: 60, ideal: 100)
        TableColumn("CPU", value: \.cpu) { (p: ProcessSample) in
            NumberCell(text: String(format: "%02.0f", p.cpu))
        }
        .width(min: 36, ideal: 46)
    }

    @TableColumnBuilder<ProcessSample, Comparator>
    private var resourceColumns: some TableColumnContent<ProcessSample, Comparator> {
        TableColumn("CPU time", value: \.cpuTime) { (p: ProcessSample) in
            NumberCell(text: Fmt.cpuTime(p.cpuTime))
        }
        .width(min: 60, ideal: 74)
        TableColumn("Memory", value: \.memory) { (p: ProcessSample) in
            NumberCell(text: Fmt.kilobytes(p.memory))
        }
        .width(min: 70, ideal: 100)
        TableColumn("Threads", value: \.threads) { (p: ProcessSample) in
            NumberCell(text: p.threads > 0 ? String(p.threads) : "")
        }
        .width(min: 44, ideal: 56)
        TableColumn("Architecture", value: \.architecture) { (p: ProcessSample) in
            Text(p.architecture)
        }
        .width(min: 60, ideal: 90)
        TableColumn("Priority", value: \.nice) { (p: ProcessSample) in
            Text(p.priorityName)
        }
        .width(min: 60, ideal: 90)
        TableColumn("Path", value: \.pathText) { (p: ProcessSample) in
            Text(p.pathText).foregroundStyle(Fluent.textSecondary).truncationMode(.middle)
        }
        .width(min: 120, ideal: 320)
    }

    private var filtered: [ProcessSample] {
        let query = state.searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return monitor.processes }
        return monitor.processes.filter { ProcessRows.matches(query, process: $0) || $0.user.localizedCaseInsensitiveContains(query) }
    }

    private func focusRequestedProcess(_ proxy: ScrollViewProxy) {
        guard let pid = state.detailsFocusPID else { return }
        selection = pid
        state.detailsFocusPID = nil
        Task { @MainActor in proxy.scrollTo(pid, anchor: .center) }
    }

    private func target(for process: ProcessSample) -> RowTarget {
        RowTarget(
            process: process,
            kind: BundlePaths.isSystem(process.path) ? .system : .background,
            isApp: NSRunningApplication(processIdentifier: process.pid) != nil
        )
    }

    /// The process plus all of its descendants.
    private func treeTarget(for process: ProcessSample) -> RowTarget {
        var children: [Int32: [Int32]] = [:]
        for p in monitor.processes where p.pid != p.ppid { children[p.ppid, default: []].append(p.pid) }
        var pids = [process.pid]
        var queue = [process.pid]
        while let pid = queue.popLast() {
            for child in children[pid] ?? [] {
                pids.append(child)
                queue.append(child)
            }
        }
        var target = target(for: process)
        target.pids = pids
        return target
    }

    @ViewBuilder
    private func menu(for process: ProcessSample) -> some View {
        let target = target(for: process)
        Button("End task") { ProcessActions.requestEndTask(target) }
        Button("End process tree") { ProcessActions.requestEndTask(treeTarget(for: process)) }
        Toggle("Efficiency mode", isOn: Binding(
            get: { process.efficiencyMode },
            set: { ProcessActions.setEfficiency(target, enabled: $0) }
        ))
        Button(process.isSuspended ? "Resume process" : "Suspend process") {
            ProcessActions.setSuspended(target, suspended: !process.isSuspended)
        }
        Menu("Set priority") {
            ForEach(Self.priorities, id: \.1) { name, nice in
                Toggle(name, isOn: Binding(
                    get: { ProcessSample.priorityName(process.nice) == name },
                    set: { _ in ProcessActions.setPriority(pid: process.pid, name: process.name, nice: nice) }
                ))
            }
        }
        Divider()
        Button("Open file location") { ProcessActions.revealInFinder(process.path) }
            .disabled(process.path == nil)
        Button("Search online") { ProcessActions.searchOnline(process.name) }
        Button("Properties") { state.properties = PropertiesTarget(pid: process.pid) }
        Divider()
        Button("Copy name") { ProcessActions.copy(process.name) }
        Button("Copy PID") { ProcessActions.copy(String(process.pid)) }
        Button("Copy path") { ProcessActions.copy(process.pathText) }
            .disabled(process.path == nil)
    }
}

/// Right-aligned monospaced number for table cells.
struct NumberCell: View {
    let text: String

    var body: some View {
        Text(text).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
    }
}
