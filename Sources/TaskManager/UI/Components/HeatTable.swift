import AppKit
import SwiftUI

/// One display row of the heat-map table.
struct HeatRow: Identifiable {
    enum Style { case section, parent, child }

    let id: String
    var style: Style
    var title: String
    var count = 0
    var iconPath: String?
    var symbol: String?
    var isExpandable = false
    var isExpanded = false
    var statusText = ""
    var efficiency: EfficiencyState = .off
    var suspended = false
    var cpu: Double = 0
    var memory: UInt64 = 0
    var disk: Double = 0
    var network: Double = 0
    var powerUsage: PowerUsage = .veryLow
    var powerTrend: PowerUsage = .veryLow
    var pid: Int32?
    var processName = ""
    var publisher = ""
    var user = ""
    var threads = 0
    var architecture = ""
    var target: RowTarget?
}

/// Header totals as fractions 0...1.
struct HeaderTotals {
    var cpu: Double
    var memory: Double
    var disk: Double
    var network: Double
}

struct TableSort: Equatable {
    var column: ProcColumn = .name
    var ascending = true
}

/// The Processes/Users table: two-line headers with totals, heat-map cells,
/// collapsible groups, column resizing and keyboard navigation.
struct HeatTable<RowMenu: View>: View {
    let rows: [HeatRow]
    let columns: [ProcColumn]
    var nameTitle = "Name"
    let totals: HeaderTotals
    @Binding var sort: TableSort
    @Binding var selection: String?
    let memoryTotal: UInt64
    var configurableColumns = true
    var onToggle: (String) -> Void
    var onActivate: (HeatRow) -> Void = { _ in }
    var onDelete: () -> Void = {}
    @ViewBuilder var rowMenu: (HeatRow) -> RowMenu

    @Environment(AppSettings.self) private var settings
    @FocusState private var focused: Bool
    @State private var lastClick: (id: String, time: Date)?
    @State private var dragStartWidth: CGFloat?

    private static var minimumNameWidth: CGFloat { 220 }

    var body: some View {
        GeometryReader { geometry in
            let fixed = columns.filter { $0 != .name }.reduce(CGFloat(0)) { $0 + settings.width(of: $1) }
            let nameWidth = max(Self.minimumNameWidth, geometry.size.width - fixed)
            let totalWidth = nameWidth + fixed
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    header(nameWidth: nameWidth)
                    Rectangle().fill(Fluent.divider).frame(height: 1)
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(rows) { row in
                                    rowView(row, nameWidth: nameWidth).id(row.id)
                                }
                            }
                            .padding(.bottom, 8)
                        }
                        .onChange(of: selection) { _, id in
                            if let id { proxy.scrollTo(id) }
                        }
                    }
                }
                .frame(width: totalWidth, height: geometry.size.height)
            }
            .scrollDisabled(totalWidth <= geometry.size.width + 1)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
        .onKeyPress(.rightArrow) { setExpanded(true) }
        .onKeyPress(.leftArrow) { setExpanded(false) }
        .onKeyPress(.delete) { onDelete(); return .handled }
        .onKeyPress(.deleteForward) { onDelete(); return .handled }
        .onKeyPress(.return) {
            if let row = rows.first(where: { $0.id == selection }) { onActivate(row) }
            return .handled
        }
    }

    // MARK: Header

    private func header(nameWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(columns) { column in
                headerCell(column)
                    .frame(width: column == .name ? nameWidth : settings.width(of: column), height: 46)
                    .overlay(alignment: .trailing) {
                        if column != columns.last { resizeHandle(column) }
                    }
            }
        }
        .contextMenu {
            if configurableColumns {
                ForEach(ProcColumn.allCases.filter(\.isOptional)) { column in
                    Toggle(column.title, isOn: Binding(
                        get: { settings.visibleColumns.contains(column) },
                        set: { _ in settings.toggleColumn(column) }
                    ))
                }
                Divider()
                Button("Reset column widths") { settings.columnWidths = [:] }
            }
        }
    }

    private func headerCell(_ column: ProcColumn) -> some View {
        let isSorted = sort.column == column
        let total = totalFraction(column)
        return Button {
            if sort.column == column {
                sort.ascending.toggle()
            } else {
                sort = TableSort(column: column, ascending: !column.sortsDescendingFirst)
            }
        } label: {
            VStack(alignment: column.isNumeric ? .trailing : .leading, spacing: 0) {
                Text(total.map(Fmt.wholePercent) ?? " ")
                    .font(.system(size: 14))
                    .foregroundStyle(Fluent.textPrimary)
                Text(column == .name ? nameTitle : column.title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Fluent.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: column.isNumeric ? .bottomTrailing : .bottomLeading)
            .padding(.horizontal, 9)
            .padding(.bottom, 5)
            .overlay(alignment: .top) {
                if isSorted {
                    Image(systemName: sort.ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Fluent.textSecondary)
                        .padding(.top, 2)
                }
            }
            .background(total.map { $0 >= 0.6 ? Heat.color(($0 - 0.5) * 2) : Color.clear } ?? Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func resizeHandle(_ column: ProcColumn) -> some View {
        Rectangle()
            .fill(Fluent.divider)
            .frame(width: 1)
            .padding(.vertical, 10)
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { inside in
                if column != .name {
                    inside ? NSCursor.resizeLeftRight.push() : NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        guard column != .name else { return }
                        let start = dragStartWidth ?? settings.width(of: column)
                        if dragStartWidth == nil { dragStartWidth = start }
                        settings.columnWidths[column.rawValue] = Double(max(48, start + value.translation.width))
                    }
                    .onEnded { _ in dragStartWidth = nil }
            )
            .offset(x: 4)
    }

    private func totalFraction(_ column: ProcColumn) -> Double? {
        switch column {
        case .cpu: return totals.cpu
        case .memory: return totals.memory
        case .disk: return totals.disk
        case .network: return totals.network
        default: return nil
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func rowView(_ row: HeatRow, nameWidth: CGFloat) -> some View {
        if row.style == .section {
            HStack {
                Text(row.count > 0 ? "\(row.title) (\(row.count))" : row.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Fluent.textPrimary)
                Spacer()
            }
            .padding(.leading, 12)
            .padding(.bottom, 6)
            .frame(height: 40, alignment: .bottom)
        } else {
            HeatRowView(
                row: row,
                columns: columns,
                nameWidth: nameWidth,
                widths: Dictionary(uniqueKeysWithValues: columns.map { ($0, settings.width(of: $0)) }),
                isSelected: selection == row.id,
                memoryTotal: memoryTotal,
                onToggle: { onToggle(row.id) }
            )
            .contentShape(Rectangle())
            .onTapGesture { click(row) }
            .contextMenu { rowMenu(row) }
        }
    }

    private func click(_ row: HeatRow) {
        focused = true
        let now = Date()
        if let last = lastClick, last.id == row.id, now.timeIntervalSince(last.time) < NSEvent.doubleClickInterval {
            lastClick = nil
            if row.isExpandable { onToggle(row.id) } else { onActivate(row) }
        } else {
            lastClick = (row.id, now)
        }
        selection = row.id
    }

    private func moveSelection(_ delta: Int) {
        let selectable = rows.filter { $0.style != .section }
        guard !selectable.isEmpty else { return }
        guard let current = selectable.firstIndex(where: { $0.id == selection }) else {
            selection = selectable.first?.id
            return
        }
        selection = selectable[min(max(current + delta, 0), selectable.count - 1)].id
    }

    private func setExpanded(_ expand: Bool) -> KeyPress.Result {
        guard let row = rows.first(where: { $0.id == selection }), row.isExpandable, row.isExpanded != expand else { return .ignored }
        onToggle(row.id)
        return .handled
    }
}

private struct HeatRowView: View {
    let row: HeatRow
    let columns: [ProcColumn]
    let nameWidth: CGFloat
    let widths: [ProcColumn: CGFloat]
    let isSelected: Bool
    let memoryTotal: UInt64
    let onToggle: () -> Void
    @State private var hovering = DebugHooks.forceHover

    var body: some View {
        HStack(spacing: 0) {
            ForEach(columns) { column in
                cell(column)
                    .lineLimit(1)
                    .frame(width: column == .name ? nameWidth : (widths[column] ?? column.defaultWidth), alignment: column.isNumeric ? .trailing : .leading)
                    .frame(maxHeight: .infinity)
                    .background(heat(column))
            }
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Fluent.textPrimary)
        .frame(height: 28)
        .overlay {
            // Drawn over the heat cells, so it must not swallow clicks meant for the chevron.
            if isSelected {
                Rectangle().fill(Fluent.rowSelected).allowsHitTesting(false)
            } else if hovering {
                Rectangle().fill(Fluent.rowHover).allowsHitTesting(false)
            }
        }
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private func cell(_ column: ProcColumn) -> some View {
        switch column {
        case .name: nameCell
        case .status: statusCell
        case .cpu: numeric(Fmt.percent(row.cpu))
        case .memory: numeric(Fmt.megabytes(row.memory))
        case .disk: numeric(Fmt.diskRate(row.disk))
        case .network: numeric(Fmt.networkRate(row.network))
        case .pid: numeric(row.pid.map(String.init) ?? "")
        case .threads: numeric(row.threads > 0 ? "\(row.threads)" : "")
        case .publisher: text(row.publisher)
        case .processName: text(row.processName)
        case .user: text(row.user)
        case .architecture: text(row.architecture)
        case .power: text(row.powerUsage.title)
        case .powerTrend: text(row.powerTrend.title)
        }
    }

    private var nameCell: some View {
        HStack(spacing: 6) {
            if row.style == .child { Color.clear.frame(width: 24) }
            if row.isExpandable {
                Button(action: onToggle) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(row.isExpanded ? 90 : 0))
                        .frame(width: 22, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Fluent.textSecondary)
                .padding(.horizontal, -3)
                .help(row.isExpanded ? "Collapse" : "Expand")
            } else {
                Color.clear.frame(width: 16)
            }
            ProcessIcon(path: row.iconPath, symbol: row.symbol)
                .frame(width: 16, height: 16)
            Text(row.title).truncationMode(.tail)
            if row.count > 1 {
                Text("(\(row.count))").foregroundStyle(Fluent.textSecondary)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
    }

    private var statusCell: some View {
        let hung = row.statusText == "Not responding"
        return HStack(spacing: 5) {
            if hung {
                Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(ResourceColor.thermal)
            } else if row.suspended {
                Image(systemName: "pause.circle").foregroundStyle(Fluent.textSecondary)
            } else if row.efficiency != .off {
                Image(systemName: row.efficiency == .on ? "leaf.fill" : "leaf")
                    .foregroundStyle(Fluent.efficiency)
                    .help(row.efficiency == .on ? "Efficiency mode" : "Some processes are in efficiency mode")
            }
            Text(row.statusText).foregroundStyle(hung ? ResourceColor.thermal : Fluent.textSecondary).truncationMode(.tail)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 9)
        .help(row.statusText)
    }

    private func numeric(_ value: String) -> some View {
        Text(value).monospacedDigit().padding(.horizontal, 9)
    }

    private func text(_ value: String) -> some View {
        Text(value).truncationMode(.tail).padding(.horizontal, 9)
    }

    private func heat(_ column: ProcColumn) -> Color {
        guard row.style != .section else { return .clear }
        switch column {
        case .cpu: return Heat.color(row.cpu / 35)
        case .memory: return Heat.color(Double(row.memory) / Double(max(memoryTotal, 1)) * 5)
        case .disk: return Heat.color(row.disk / 20_971_520)
        case .network: return Heat.color(row.network * 8 / 25_000_000)
        case .power: return Heat.color(row.powerUsage.heat)
        case .powerTrend: return Heat.color(row.powerTrend.heat)
        default: return .clear
        }
    }
}
