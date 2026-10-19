import AppKit
import SwiftUI

struct PerformancePage: View {
    @Environment(Monitor.self) private var monitor
    @Environment(AppState.self) private var state
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let item = effectiveItem
        VStack(spacing: 0) {
            PageHeader(title: "Performance") {
                CommandButton(title: "Run new task", systemImage: "macwindow.badge.plus") { state.showRunTask = true }
                CommandBarMenu(title: "View", systemImage: "ellipsis") {
                    if item == .cpu {
                        CPUGraphMenu()
                        Divider()
                    }
                    Button("Copy") { ProcessActions.copy(PerformanceSummary.text(for: item, monitor: monitor)) }
                    Button("Refresh now") { monitor.refreshNow() }
                }
            }
            HStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 2) { tiles }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
                .frame(width: 270)
                Rectangle().fill(Fluent.divider).frame(width: 1)
                detail(item)
                    .padding(.horizontal, 26)
                    .padding(.top, 6)
                    .padding(.bottom, 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    /// Falls back to CPU if the selected disk or adapter went away.
    private var effectiveItem: PerfItem {
        switch state.perfItem {
        case .disk(let id): return monitor.system.disks.contains { $0.id == id } ? state.perfItem : .cpu
        case .network(let id): return monitor.system.networks.contains { $0.id == id } ? state.perfItem : .cpu
        case .gpu: return monitor.system.gpu == nil ? .cpu : .gpu
        default: return state.perfItem
        }
    }

    @ViewBuilder
    private var tiles: some View {
        let system = monitor.system
        let hw = HardwareInfo.shared
        ResourceTile(
            title: "CPU",
            lines: [Fmt.wholePercent(system.cpu.total) + (hw.maxSpeedHz.map { "  " + Fmt.frequency($0) } ?? "")],
            tint: ResourceColor.cpu,
            series: [GraphSeries(values: monitor.cpuHistory.values, color: ResourceColor.cpu)],
            isSelected: effectiveItem == .cpu
        ) { state.perfItem = .cpu }

        ResourceTile(
            title: "Memory",
            lines: [String(format: "%.1f/%.1f GB (%@)", Double(system.memory.used) / 1_073_741_824, Double(system.memory.total) / 1_073_741_824, Fmt.wholePercent(system.memory.usedFraction))],
            tint: ResourceColor.memory,
            series: [GraphSeries(values: monitor.memoryHistory.values, color: ResourceColor.memory)],
            isSelected: effectiveItem == .memory
        ) { state.perfItem = .memory }

        ForEach(system.disks) { disk in
            ResourceTile(
                title: disk.title,
                lines: ["\(disk.kindText) (\(disk.interconnect))", Fmt.wholePercent(disk.activeTime)],
                tint: ResourceColor.disk,
                series: [GraphSeries(values: monitor.diskActiveHistory[disk.id]?.values ?? [], color: ResourceColor.disk)],
                isSelected: effectiveItem == .disk(disk.id)
            ) { state.perfItem = .disk(disk.id) }
        }

        ForEach(system.networks) { net in
            let receive = monitor.netReceiveHistory[net.id]?.values ?? []
            let send = monitor.netSendHistory[net.id]?.values ?? []
            ResourceTile(
                title: net.name,
                lines: [net.kind == net.name ? net.id : net.kind, Fmt.bitRatePair(send: net.sendRate, receive: net.receiveRate)],
                tint: ResourceColor.network,
                series: [
                    GraphSeries(values: receive, color: ResourceColor.network),
                    GraphSeries(values: send, color: ResourceColor.network, fillOpacity: 0, dashed: true),
                ],
                maxValue: Fmt.niceCeiling(max(receive.max() ?? 0, send.max() ?? 0), minimum: 100_000),
                isSelected: effectiveItem == .network(net.id)
            ) { state.perfItem = .network(net.id) }
        }

        if let gpu = system.gpu {
            ResourceTile(
                title: "GPU 0",
                lines: [gpu.name, Fmt.wholePercent(gpu.utilization)],
                tint: ResourceColor.gpu,
                series: [GraphSeries(values: monitor.gpuHistory.values, color: ResourceColor.gpu)],
                isSelected: effectiveItem == .gpu
            ) { state.perfItem = .gpu }
        }
    }

    @ViewBuilder
    private func detail(_ item: PerfItem) -> some View {
        switch item {
        case .cpu: CPUDetail()
        case .memory: MemoryDetail()
        case .disk(let id): DiskDetail(id: id)
        case .network(let id): NetworkDetail(id: id)
        case .gpu: GPUDetail()
        }
    }
}

struct CPUGraphMenu: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Picker("Change graph to", selection: Binding(get: { settings.cpuGraphMode }, set: { settings.cpuGraphMode = $0 })) {
            Text("Overall utilization").tag(CPUGraphMode.overall)
            Text("Logical processors").tag(CPUGraphMode.logical)
        }
        Toggle("Show kernel times", isOn: Binding(get: { settings.showKernelTimes }, set: { settings.showKernelTimes = $0 }))
    }
}

// MARK: - Building blocks

private struct ResourceTile: View {
    let title: String
    let lines: [String]
    let tint: Color
    let series: [GraphSeries]
    var maxValue: Double = 1
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                PerfGraph(series: series, maxValue: maxValue, tint: tint, showGrid: false)
                    .frame(width: 70, height: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Fluent.textPrimary)
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Fluent.textSecondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Fluent.subtleSelected : (hovering ? Fluent.subtleHover : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct DetailHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 26, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(subtitle)
                .font(.system(size: 15))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(Fluent.textPrimary)
        .padding(.bottom, 4)
    }
}

/// Large figure with a small label above it, optionally with a solid/dashed legend bar.
private struct BigStat: View {
    let label: String
    let value: String
    var legend: Color?
    var dashed = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let legend {
                Path { path in
                    path.move(to: CGPoint(x: 1, y: 2))
                    path.addLine(to: CGPoint(x: 1, y: 36))
                }
                .stroke(legend, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 2] : []))
                .frame(width: 2, height: 38)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Fluent.textSecondary)
                Text(value)
                    .font(.system(size: 19))
                    .monospacedDigit()
                    .foregroundStyle(Fluent.textPrimary)
            }
        }
        .fixedSize()
    }
}

private struct StatsArea<Stats: View>: View {
    let details: [(String, String)]
    @ViewBuilder var stats: Stats

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 12) { stats }
            KeyValueGrid(rows: details)
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
    }
}

// MARK: - Detail pages

private struct CPUDetail: View {
    @Environment(Monitor.self) private var monitor
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let hw = HardwareInfo.shared
        VStack(alignment: .leading, spacing: 5) {
            DetailHeader(title: "CPU", subtitle: hw.cpuName)
            GraphCaption(leading: "% Utilization", trailing: "100%")
            Group {
                if settings.cpuGraphMode == .logical {
                    CoreGrid()
                } else {
                    PerfGraph(
                        series: series(monitor.cpuHistory, monitor.cpuKernelHistory),
                        tint: ResourceColor.cpu,
                        phase: monitor.tick
                    )
                }
            }
            .frame(maxHeight: .infinity)
            .contextMenu { CPUGraphMenu() }
            GraphCaption(leading: Fmt.span(monitor.graphSpan), trailing: "0")

            StatsArea(details: details(hw)) {
                HStack(alignment: .top, spacing: 30) {
                    BigStat(label: "Utilization", value: Fmt.wholePercent(monitor.system.cpu.total))
                    BigStat(label: "Max speed", value: hw.maxSpeedHz.map(Fmt.frequency) ?? "—")
                }
                HStack(alignment: .top, spacing: 30) {
                    BigStat(label: "Processes", value: "\(monitor.processes.count)")
                    BigStat(label: "Threads", value: "\(monitor.threadCount)")
                    BigStat(label: "Load average", value: String(format: "%.2f", monitor.system.cpu.loadAverage))
                }
                BigStat(label: "Up time", value: Fmt.uptime(Date().timeIntervalSince(hw.bootTime)))
            }
        }
    }

    private func series(_ total: History, _ kernel: History) -> [GraphSeries] {
        var result = [GraphSeries(values: total.values, color: ResourceColor.cpu)]
        if settings.showKernelTimes {
            result.append(GraphSeries(values: kernel.values, color: ResourceColor.cpu, fillOpacity: 0.28, lineWidth: 0.6))
        }
        return result
    }

    private func details(_ hw: HardwareInfo) -> [(String, String)] {
        var rows: [(String, String)] = []
        if hw.efficiencyCores > 0 {
            rows.append(("Performance cores:", "\(hw.performanceCores)" + (hw.performanceMaxHz.map { " (up to \(Fmt.frequency($0)))" } ?? "")))
            rows.append(("Efficiency cores:", "\(hw.efficiencyCores)" + (hw.efficiencyMaxHz.map { " (up to \(Fmt.frequency($0)))" } ?? "")))
        }
        rows.append(("Sockets:", "1"))
        rows.append(("Cores:", "\(hw.physicalCores)"))
        rows.append(("Logical processors:", "\(hw.logicalCores)"))
        rows.append(("Virtualization:", hw.virtualization ? "Enabled" : "Not available"))
        if hw.l1Cache > 0 { rows.append(("L1 cache:", Fmt.bytes(hw.l1Cache))) }
        if hw.l2Cache > 0 { rows.append(("L2 cache:", Fmt.bytes(hw.l2Cache))) }
        if hw.l3Cache > 0 { rows.append(("L3 cache:", Fmt.bytes(hw.l3Cache))) }
        return rows
    }
}

/// One small graph per logical processor.
private struct CoreGrid: View {
    @Environment(Monitor.self) private var monitor
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let count = monitor.coreHistory.count
        let columns = count <= 4 ? max(count, 1) : (count <= 16 && count % 4 == 0 ? 4 : Int((Double(count) / 3).rounded(.up)))
        let rows = Int((Double(count) / Double(columns)).rounded(.up))
        VStack(spacing: 6) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < count {
                            PerfGraph(
                                series: series(index),
                                tint: ResourceColor.cpu,
                                phase: monitor.tick,
                                gridRows: 4,
                                gridColumns: 6
                            )
                            .help("CPU \(index)")
                        } else {
                            Color.clear
                        }
                    }
                }
            }
        }
    }

    private func series(_ index: Int) -> [GraphSeries] {
        var result = [GraphSeries(values: monitor.coreHistory[index].values, color: ResourceColor.cpu)]
        if settings.showKernelTimes, index < monitor.coreKernelHistory.count {
            result.append(GraphSeries(values: monitor.coreKernelHistory[index].values, color: ResourceColor.cpu, fillOpacity: 0.28, lineWidth: 0.6))
        }
        return result
    }
}

private struct MemoryDetail: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        let memory = monitor.system.memory
        VStack(alignment: .leading, spacing: 5) {
            DetailHeader(title: "Memory", subtitle: Fmt.gigabytes(memory.total))
            GraphCaption(leading: "Memory usage", trailing: Fmt.gigabytes(memory.total))
            PerfGraph(
                series: [GraphSeries(values: monitor.memoryHistory.values, color: ResourceColor.memory)],
                tint: ResourceColor.memory,
                phase: monitor.tick
            )
            .frame(maxHeight: .infinity)
            GraphCaption(leading: Fmt.span(monitor.graphSpan), trailing: "0")
            GraphCaption(leading: "Memory composition").padding(.top, 8)
            MemoryCompositionBar(memory: memory).frame(height: 38)

            StatsArea(details: [
                ("Memory pressure:", memory.pressureText),
                ("Total:", Fmt.gigabytes(memory.total)),
                ("Form factor:", isAppleSilicon ? "Unified memory" : "DIMM"),
                ("Model:", HardwareInfo.shared.modelIdentifier),
            ]) {
                HStack(alignment: .top, spacing: 30) {
                    BigStat(label: "In use (Compressed)", value: "\(Fmt.gigabytes(memory.used)) (\(Fmt.gigabytes(memory.compressed)))")
                    BigStat(label: "Available", value: Fmt.gigabytes(memory.available))
                }
                HStack(alignment: .top, spacing: 30) {
                    BigStat(label: "Swap used", value: String(format: "%.1f/%.1f GB", Double(memory.swapUsed) / 1_073_741_824, Double(memory.swapTotal) / 1_073_741_824))
                    BigStat(label: "Cached", value: Fmt.gigabytes(memory.cached))
                }
                HStack(alignment: .top, spacing: 30) {
                    BigStat(label: "App memory", value: Fmt.gigabytes(memory.app))
                    BigStat(label: "Wired", value: Fmt.gigabytes(memory.wired))
                }
            }
        }
    }

    private var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
}

private struct MemoryCompositionBar: View {
    let memory: MemorySnapshot

    var body: some View {
        let parts: [(String, UInt64, Double)] = [
            ("App memory", memory.app, 0.42),
            ("Wired", memory.wired, 0.58),
            ("Compressed", memory.compressed, 0.26),
            ("Cached files", memory.cached, 0.12),
            ("Free", memory.free, 0),
        ]
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(parts, id: \.0) { part in
                    let fraction = memory.total > 0 ? Double(part.1) / Double(memory.total) : 0
                    Rectangle()
                        .fill(ResourceColor.memory.opacity(part.2))
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(ResourceColor.memory.opacity(0.6)).frame(width: part.0 == "Free" ? 0 : 1)
                        }
                        .frame(width: max(0, geometry.size.width * fraction))
                        .help("\(part.0): \(Fmt.gigabytes(part.1))")
                }
                Spacer(minLength: 0)
            }
        }
        .background(Fluent.graphBackground)
        .overlay(Rectangle().strokeBorder(ResourceColor.memory, lineWidth: 1))
    }
}

private struct DiskDetail: View {
    let id: String
    @Environment(Monitor.self) private var monitor

    var body: some View {
        if let disk = monitor.system.disks.first(where: { $0.id == id }) {
            let read = monitor.diskReadHistory[id]?.values ?? []
            let write = monitor.diskWriteHistory[id]?.values ?? []
            let scale = Fmt.niceCeiling(max(read.max() ?? 0, write.max() ?? 0), minimum: 1_048_576)
            VStack(alignment: .leading, spacing: 5) {
                DetailHeader(title: disk.title, subtitle: disk.model)
                GraphCaption(leading: "Active time", trailing: "100%")
                PerfGraph(
                    series: [GraphSeries(values: monitor.diskActiveHistory[id]?.values ?? [], color: ResourceColor.disk)],
                    tint: ResourceColor.disk,
                    phase: monitor.tick
                )
                .frame(maxHeight: .infinity)
                GraphCaption(leading: Fmt.span(monitor.graphSpan), trailing: "0")
                GraphCaption(leading: "Disk transfer rate", trailing: Fmt.byteRate(scale)).padding(.top, 8)
                PerfGraph(
                    series: [
                        GraphSeries(values: read, color: ResourceColor.disk),
                        GraphSeries(values: write, color: ResourceColor.disk, fillOpacity: 0, dashed: true),
                    ],
                    maxValue: scale,
                    tint: ResourceColor.disk,
                    phase: monitor.tick,
                    gridRows: 4
                )
                .frame(minHeight: 70, maxHeight: 120)
                GraphCaption(leading: Fmt.span(monitor.graphSpan), trailing: "0")

                StatsArea(details: [
                    ("Capacity:", Fmt.bytes(disk.capacity)),
                    ("Formatted:", disk.formatted > 0 ? Fmt.bytes(disk.formatted) : "—"),
                    ("System disk:", disk.isSystemDisk ? "Yes" : "No"),
                    ("Type:", disk.kindText),
                    ("Interface:", disk.interconnect),
                    ("Location:", disk.isInternal ? "Internal" : "External"),
                ]) {
                    HStack(alignment: .top, spacing: 30) {
                        BigStat(label: "Active time", value: Fmt.wholePercent(disk.activeTime))
                        BigStat(label: "Average response time", value: String(format: "%.1f ms", disk.responseTimeMs))
                    }
                    HStack(alignment: .top, spacing: 30) {
                        BigStat(label: "Read speed", value: Fmt.byteRate(disk.readRate), legend: ResourceColor.disk)
                        BigStat(label: "Write speed", value: Fmt.byteRate(disk.writeRate), legend: ResourceColor.disk, dashed: true)
                    }
                }
            }
        }
    }
}

private struct NetworkDetail: View {
    let id: String
    @Environment(Monitor.self) private var monitor

    var body: some View {
        if let net = monitor.system.networks.first(where: { $0.id == id }) {
            let receive = monitor.netReceiveHistory[id]?.values ?? []
            let send = monitor.netSendHistory[id]?.values ?? []
            let scale = Fmt.niceCeiling(max(receive.max() ?? 0, send.max() ?? 0), minimum: 100_000)
            VStack(alignment: .leading, spacing: 5) {
                DetailHeader(title: net.name, subtitle: net.kind == net.name ? net.id : "\(net.kind) · \(net.id)")
                GraphCaption(leading: "Throughput", trailing: Fmt.bitRate(scale))
                PerfGraph(
                    series: [
                        GraphSeries(values: receive, color: ResourceColor.network),
                        GraphSeries(values: send, color: ResourceColor.network, fillOpacity: 0, dashed: true),
                    ],
                    maxValue: scale,
                    tint: ResourceColor.network,
                    phase: monitor.tick
                )
                .frame(maxHeight: .infinity)
                GraphCaption(leading: Fmt.span(monitor.graphSpan), trailing: "0")

                StatsArea(details: [
                    ("Adapter name:", net.name),
                    ("Interface:", net.id),
                    ("Connection type:", net.kind),
                    ("IPv4 address:", net.ipv4.isEmpty ? "—" : net.ipv4.joined(separator: ", ")),
                    ("IPv6 address:", net.ipv6.first ?? "—"),
                    ("Link speed:", Fmt.linkSpeed(net.linkSpeed)),
                ]) {
                    BigStat(label: "Send", value: Fmt.bitRate(net.sendRate), legend: ResourceColor.network, dashed: true)
                    BigStat(label: "Receive", value: Fmt.bitRate(net.receiveRate), legend: ResourceColor.network)
                }
            }
        }
    }
}

private struct GPUDetail: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        let hw = HardwareInfo.shared
        if let gpu = monitor.system.gpu {
            let budget = max(Double(hw.gpuMemoryBudget), monitor.gpuMemoryHistory.peak, 1)
            VStack(alignment: .leading, spacing: 5) {
                DetailHeader(title: "GPU", subtitle: gpu.name)
                HStack(spacing: 14) {
                    engine("Device", gpu.utilization, monitor.gpuHistory)
                    engine("Renderer", gpu.renderer, monitor.gpuRendererHistory)
                    engine("Tiler", gpu.tiler, monitor.gpuTilerHistory)
                }
                .frame(maxHeight: .infinity)
                GraphCaption(leading: "Shared GPU memory usage", trailing: Fmt.gigabytes(UInt64(budget))).padding(.top, 8)
                PerfGraph(
                    series: [GraphSeries(values: monitor.gpuMemoryHistory.values, color: ResourceColor.gpu)],
                    maxValue: budget,
                    tint: ResourceColor.gpu,
                    phase: monitor.tick,
                    gridRows: 4
                )
                .frame(minHeight: 60, maxHeight: 100)

                StatsArea(details: [
                    ("GPU cores:", gpu.cores.map(String.init) ?? "—"),
                    ("Graphics API:", hw.metalSupport),
                    ("Memory:", "Shared with system"),
                    ("Memory budget:", Fmt.gigabytes(hw.gpuMemoryBudget)),
                ]) {
                    HStack(alignment: .top, spacing: 30) {
                        BigStat(label: "Utilization", value: Fmt.wholePercent(gpu.utilization))
                        BigStat(label: "Shared GPU memory", value: String(format: "%.1f/%.1f GB", Double(gpu.memoryUsed) / 1_073_741_824, budget / 1_073_741_824))
                    }
                }
            }
        }
    }

    private func engine(_ name: String, _ value: Double, _ history: History) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            GraphCaption(leading: name, trailing: Fmt.wholePercent(value))
            PerfGraph(
                series: [GraphSeries(values: history.values, color: ResourceColor.gpu)],
                tint: ResourceColor.gpu,
                phase: monitor.tick,
                gridRows: 5,
                gridColumns: 8
            )
        }
    }
}

/// Plain-text summary for "Copy", in the same shape Windows produces.
@MainActor
enum PerformanceSummary {
    static func text(for item: PerfItem, monitor: Monitor) -> String {
        let hw = HardwareInfo.shared
        let s = monitor.system
        var lines: [String] = []
        func add(_ key: String, _ value: String) { lines.append("\t\(key)\t\(value)") }
        switch item {
        case .cpu:
            lines += ["CPU", "", "\t\(hw.cpuName)", ""]
            add("Utilization", Fmt.wholePercent(s.cpu.total))
            add("Max speed", hw.maxSpeedHz.map(Fmt.frequency) ?? "—")
            add("Processes", "\(monitor.processes.count)")
            add("Threads", "\(monitor.threadCount)")
            add("Up time", Fmt.uptime(Date().timeIntervalSince(hw.bootTime)))
            add("Cores", "\(hw.physicalCores)")
            add("Logical processors", "\(hw.logicalCores)")
        case .memory:
            lines += ["Memory", "", "\t\(Fmt.gigabytes(s.memory.total))", ""]
            add("In use (Compressed)", "\(Fmt.gigabytes(s.memory.used)) (\(Fmt.gigabytes(s.memory.compressed)))")
            add("Available", Fmt.gigabytes(s.memory.available))
            add("Cached", Fmt.gigabytes(s.memory.cached))
            add("Wired", Fmt.gigabytes(s.memory.wired))
            add("Swap used", Fmt.gigabytes(s.memory.swapUsed))
            add("Memory pressure", s.memory.pressureText)
        case .disk(let id):
            guard let d = s.disks.first(where: { $0.id == id }) else { break }
            lines += [d.title, "", "\t\(d.model)", ""]
            add("Capacity", Fmt.bytes(d.capacity))
            add("Active time", Fmt.wholePercent(d.activeTime))
            add("Average response time", String(format: "%.1f ms", d.responseTimeMs))
            add("Read speed", Fmt.byteRate(d.readRate))
            add("Write speed", Fmt.byteRate(d.writeRate))
        case .network(let id):
            guard let n = s.networks.first(where: { $0.id == id }) else { break }
            lines += [n.name, "", "\t\(n.id)", ""]
            add("Send", Fmt.bitRate(n.sendRate))
            add("Receive", Fmt.bitRate(n.receiveRate))
            add("IPv4 address", n.ipv4.joined(separator: ", "))
            add("IPv6 address", n.ipv6.first ?? "")
        case .gpu:
            guard let g = s.gpu else { break }
            lines += ["GPU", "", "\t\(g.name)", ""]
            add("Utilization", Fmt.wholePercent(g.utilization))
            add("Shared GPU memory", Fmt.gigabytes(g.memoryUsed))
        }
        return lines.joined(separator: "\n")
    }
}
