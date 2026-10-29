import SwiftUI

/// The Processes page as a treemap: every app is a tile sized by memory, CPU, power or network.
/// Double-click an app to see its helper processes.
struct ProcessMap: View {
    let nodes: [ProcNode]
    @Binding var selection: String?
    @Environment(Monitor.self) private var monitor
    @State private var measure = Measure.memory
    @State private var focus: String?

    enum Measure: String, CaseIterable, Identifiable {
        case memory, cpu, power, network
        var id: String { rawValue }
        var title: String {
            switch self {
            case .memory: return "Memory"
            case .cpu: return "CPU"
            case .power: return "Power"
            case .network: return "Network"
            }
        }
    }

    struct Item: Identifiable {
        let id: String
        let name: String
        let value: Double
        let iconPath: String?
        let kind: ProcKind
        let node: ProcNode?
        let process: ProcessSample?
        var count = 1
    }

    /// Tiles beyond this are left out of the map and summed up in its header instead.
    static let maxTiles = 150

    var body: some View {
        let focused = focus.flatMap { id in nodes.first { $0.id == id } }
        let all = Self.items(nodes: nodes, focused: focused, measure: measure, energyAvailable: monitor.energyAvailable)
        let items = Array(all.prefix(Self.maxTiles))
        let rest = all.dropFirst(Self.maxTiles)
        let total = all.reduce(0) { $0 + $1.value }
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("All processes") { focus = nil }
                    .buttonStyle(.link)
                    .disabled(focused == nil)
                if let focused {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Fluent.textTertiary)
                    Text(focused.name).foregroundStyle(Fluent.textPrimary)
                }
                Text(total > 0 ? "· \(format(total)) in total" : "").foregroundStyle(Fluent.textSecondary)
                if !rest.isEmpty {
                    Text("· \(rest.count) small ones not shown (\(format(rest.reduce(0) { $0 + $1.value })))")
                        .foregroundStyle(Fluent.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                }
                Spacer()
                legend
                Picker("Size by", selection: $measure) {
                    ForEach(Measure.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .font(.system(size: 12))
            GeometryReader { geometry in
                let rects = Treemap.layout(items.map(\.value), in: CGRect(origin: .zero, size: geometry.size))
                let largest = items.map(\.value).max() ?? 1
                ZStack(alignment: .topLeading) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let rect = rects[index].insetBy(dx: 1, dy: 1)
                        if rect.width > 1 && rect.height > 1 {
                            MapTile(item: item, label: format(item.value), share: largest > 0 ? item.value / largest : 0,
                                    isSelected: selection == item.id, rect: rect) {
                                if item.node != nil || item.process != nil { selection = item.id }
                            } open: {
                                if let node = item.node, node.members.count > 1, focused == nil {
                                    focus = node.id
                                    selection = nil
                                }
                            }
                            .contextMenu { menu(for: item, in: focused) }
                        }
                    }
                }
                .overlay {
                    if items.isEmpty {
                        Text(measure == .memory ? "No processes match." : "Nothing is using the \(measure.title.lowercased()) right now.")
                            .foregroundStyle(Fluent.textSecondary)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).fill(Fluent.card))
            .clipShape(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous))
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
        .onChange(of: nodes.map(\.id)) { _, ids in
            if let focus, !ids.contains(focus) { self.focus = nil }
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(ProcKind.allCases, id: \.self) { kind in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Self.color(kind)).frame(width: 9, height: 9)
                    Text(Self.legendTitle(kind)).foregroundStyle(Fluent.textSecondary)
                }
            }
        }
        .fixedSize()
        .padding(.trailing, 6)
    }

    private static func legendTitle(_ kind: ProcKind) -> String {
        switch kind {
        case .app: return "Apps"
        case .background: return "Background"
        case .system: return "macOS"
        }
    }

    @ViewBuilder
    private func menu(for item: Item, in focused: ProcNode?) -> some View {
        if let node = item.node {
            if node.members.count > 1 && focused == nil {
                Button("Show its processes") { focus = node.id }
                Divider()
            }
            ProcessRowMenu(row: {
                var row = ProcessRows.row(for: node, expanded: false)
                row.isExpandable = false
                return row
            }(), toggle: { _ in })
        } else if let process = item.process, let focused {
            ProcessRowMenu(row: ProcessRows.row(for: process, in: focused), toggle: { _ in })
        }
    }

    private func format(_ value: Double) -> String {
        switch measure {
        case .memory: return Fmt.bytes(value)
        case .cpu: return Fmt.percent(value)
        case .power: return monitor.energyAvailable ? Fmt.watts(value) : Fmt.percent(value)
        case .network: return Fmt.byteRate(value)
        }
    }

    static func color(_ kind: ProcKind) -> Color {
        switch kind {
        case .app: return Fluent.accent
        case .background: return ResourceColor.memory
        case .system: return ResourceColor.disk
        }
    }

    /// Tiles for the whole machine, or for one app's processes, largest first.
    static func items(nodes: [ProcNode], focused: ProcNode?, measure: Measure, energyAvailable: Bool) -> [Item] {
        func value(_ memory: UInt64, _ cpu: Double, _ power: Double, _ network: Double) -> Double {
            switch measure {
            case .memory: return Double(memory)
            case .cpu: return cpu
            // Without energy counters (Intel), CPU stands in for power, as in the Power usage column.
            case .power: return energyAvailable ? power : cpu
            case .network: return network
            }
        }
        var items: [Item]
        if let focused {
            items = focused.members.map { p in
                Item(id: "\(focused.id)/\(p.pid)", name: p.name, value: value(p.memory, p.cpu, p.power, p.netRate),
                     iconPath: BundlePaths.innermostApp(p.path) ?? p.path, kind: focused.kind, node: nil, process: p)
            }
        } else {
            items = nodes.map { n in
                Item(id: n.id, name: n.name, value: value(n.memory, n.cpu, n.power, n.netRate),
                     iconPath: n.iconPath, kind: n.kind, node: n, process: nil, count: n.members.count)
            }
        }
        return items.filter { $0.value > 0 }.sorted { $0.value > $1.value }
    }
}

private struct MapTile: View {
    let item: ProcessMap.Item
    let label: String
    let share: Double
    let isSelected: Bool
    let rect: CGRect
    let select: () -> Void
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        let color = ProcessMap.color(item.kind)
        let hung = item.node?.notResponding == true || item.process?.notResponding == true
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color.opacity(0.28 + 0.5 * min(max(share, 0), 1)))
            if rect.width > 64 && rect.height > 30 {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        if rect.width > 90 {
                            ProcessIcon(path: item.iconPath, symbol: item.iconPath == nil ? "cpu" : nil).frame(width: 14, height: 14)
                        }
                        Text(item.count > 1 && item.node != nil ? "\(item.name) (\(item.count))" : item.name)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                    }
                    if rect.height > 44 {
                        Text(label).font(.system(size: 11)).monospacedDigit().opacity(0.8)
                    }
                }
                .foregroundStyle(Fluent.textPrimary)
                .padding(6)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(hung ? ResourceColor.thermal : (isSelected ? Fluent.accent : (hovering ? Fluent.textSecondary.opacity(0.6) : .clear)),
                              lineWidth: hung || isSelected ? 2 : 1)
        )
        .frame(width: rect.width, height: rect.height)
        .contentShape(Rectangle())
        .offset(x: rect.minX, y: rect.minY)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: open)
        .onTapGesture(perform: select)
        .help("\(item.name): \(label)")
    }
}
