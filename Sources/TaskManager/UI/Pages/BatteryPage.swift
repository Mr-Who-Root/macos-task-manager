import AppKit
import Charts
import SwiftUI

/// Charge, health, power draw and adapter; the last 24 hours; battery usage by app; and what is
/// keeping the Mac awake.
struct BatteryPage: View {
    @Environment(Monitor.self) private var monitor
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var state

    var body: some View {
        let battery = monitor.system.battery
        let query = state.searchText.trimmingCharacters(in: .whitespaces)
        VStack(spacing: 0) {
            PageHeader(title: "Battery") {
                if battery.isPresent {
                    BatteryStatusBadge(battery: battery).padding(.trailing, 8)
                    CommandButton(title: "Battery settings", systemImage: "gearshape") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if battery.isPresent {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                            ChargeCard(battery: battery)
                            PowerDrawCard(battery: battery, history: monitor.powerDrawHistory.values)
                            HealthCard(battery: battery)
                            if let celsius = monitor.batteryTemperature {
                                BatteryTemperatureCard(
                                    celsius: celsius,
                                    fromGasGauge: battery.temperature != nil,
                                    history: monitor.batteryTemperatureHistory.values,
                                    fahrenheit: settings.useFahrenheit
                                )
                            }
                            AdapterCard(battery: battery)
                        }
                        BatteryHistoryChart(points: monitor.batteryLog.points)
                    } else {
                        NoBatteryCard()
                    }
                    BatteryUsageList(
                        nodes: monitor.nodes.filter { query.isEmpty || ProcessRows.matches(query, node: $0) },
                        history: monitor.appHistory,
                        assertions: battery.assertions,
                        energyAvailable: monitor.energyAvailable
                    )
                    SleepAssertionList(
                        assertions: battery.assertions.filter { query.isEmpty || $0.processName.localizedCaseInsensitiveContains(query) },
                        nodes: monitor.nodes
                    )
                    if battery.isPresent {
                        BatteryDetails(battery: battery)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
            .defaultScrollAnchor(DebugHooks.scrollAnchor)
        }
    }
}

/// Colours for the charge level.
enum ChargeScale {
    static let low = Color(light: NSColor(srgbRed: 0.85, green: 0.38, blue: 0.05, alpha: 1), dark: NSColor(srgbRed: 1, green: 0.6, blue: 0.3, alpha: 1))

    static func color(_ battery: BatterySnapshot) -> Color {
        if battery.externalConnected { return Fluent.efficiency }
        if battery.charge <= 0.1 { return ResourceColor.thermal }
        if battery.charge <= 0.2 { return low }
        return Fluent.accent
    }

    /// Chart bars for time on battery, set against the green of "plugged in". Not the accent, which
    /// can be green; Midnight's blue and Terminal's main green are too close to their greens.
    static var onBattery: Color {
        switch Fluent.design {
        case .midnight: return ResourceColor.memory
        case .terminal: return Fluent.textSecondary
        default: return ResourceColor.cpu
        }
    }
}

// MARK: - Header

private struct BatteryStatusBadge: View {
    let battery: BatterySnapshot

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(ChargeScale.color(battery)).frame(width: 7, height: 7)
            Text(battery.lowPowerMode ? "\(battery.statusText) · Low Power Mode" : battery.statusText)
        }
        .font(.system(size: 12))
        .foregroundStyle(Fluent.textSecondary)
    }
}

// MARK: - Cards

/// The card chrome shared by the tiles at the top of the page.
private struct BatteryTile<Content: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(Fluent.accent)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Fluent.textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            content
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).fill(Fluent.card))
        .overlay(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).strokeBorder(Fluent.cardStroke))
    }
}

private struct TileValue: View {
    let value: String
    var color: Color = Fluent.textPrimary
    var caption = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value)
                .font(.system(size: 26, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
            Text(caption)
                .font(.system(size: 11.5))
                .foregroundStyle(Fluent.textSecondary)
                .lineLimit(1)
        }
    }
}

private struct TileMeter: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Fluent.subtleSelected)
                Capsule().fill(color).frame(width: max(4, geometry.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 5)
    }
}

private struct TileNote: View {
    let text: String
    var tertiary = false

    var body: some View {
        Text(text)
            .font(.system(size: tertiary ? 11 : 11.5))
            .foregroundStyle(tertiary ? Fluent.textTertiary : Fluent.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ChargeCard: View {
    let battery: BatterySnapshot

    var body: some View {
        let color = ChargeScale.color(battery)
        BatteryTile(symbol: battery.symbol, title: "Charge") {
            TileValue(value: Fmt.wholePercent(battery.charge), color: color, caption: battery.statusText)
            TileMeter(fraction: battery.charge, color: color)
            TileNote(text: detail)
            if let remaining = battery.remainingCapacity, let full = battery.fullChargeCapacity {
                TileNote(text: "\(Fmt.milliampHours(remaining)) of \(Fmt.milliampHours(full))", tertiary: true)
            }
        }
    }

    private var detail: String {
        let flow = battery.batteryPower.map(abs) ?? 0
        if battery.isCharging {
            let rate = flow >= 0.05 ? "Charging at \(Fmt.watts(flow))" : "Charging"
            return battery.timeToFull.map { "\(rate) · full in \(Fmt.duration(minutes: $0))" } ?? rate
        }
        if !battery.externalConnected {
            let left = battery.timeToEmpty.map { "\(Fmt.duration(minutes: $0)) remaining" } ?? "Estimating time remaining…"
            return flow >= 0.05 ? "\(left) · using \(Fmt.watts(flow))" : left
        }
        if battery.isFullyCharged || battery.charge >= 0.995 { return "Running on the power adapter" }
        if battery.optimizedCharging { return "Optimized Battery Charging is holding the charge" }
        return "macOS can pause charging to protect the battery"
    }
}

private struct PowerDrawCard: View {
    let battery: BatterySnapshot
    let history: [Double]

    var body: some View {
        let draw = battery.powerDraw
        BatteryTile(symbol: "bolt", title: "Power draw") {
            TileValue(value: draw.map(Fmt.watts) ?? "—", caption: battery.externalConnected ? "From power adapter" : "From battery")
            PerfGraph(
                series: [GraphSeries(values: history, color: Fluent.accent)],
                maxValue: Fmt.niceCeiling(history.max() ?? 0, minimum: 10),
                tint: Fluent.accent.opacity(0.6),
                showGrid: false
            )
            .frame(height: 44)
            TileNote(text: draw == nil ? "This Mac doesn't report its power draw while plugged in" : "Everything the Mac is using right now", tertiary: true)
        }
    }
}

private struct HealthCard: View {
    let battery: BatterySnapshot

    var body: some View {
        let normal = battery.condition == nil || battery.condition == "Normal"
        BatteryTile(symbol: "heart", title: "Health") {
            TileValue(value: battery.health.map(Fmt.wholePercent) ?? "—", caption: battery.condition ?? "")
            TileMeter(fraction: battery.health ?? 0, color: normal ? Fluent.efficiency : ResourceColor.thermal)
            TileNote(text: "Maximum capacity compared with when it was new")
            if let cycles = battery.cycleCount {
                TileNote(text: battery.designCycleCount.map { "\(cycles) of \($0.formatted()) rated charge cycles" } ?? "\(cycles) charge cycles", tertiary: true)
            }
        }
    }
}

private struct BatteryTemperatureCard: View {
    let celsius: Double
    let fromGasGauge: Bool
    let history: [Double]
    let fahrenheit: Bool

    var body: some View {
        let color = TemperatureScale.color(celsius)
        BatteryTile(symbol: "thermometer.medium", title: "Temperature") {
            TileValue(value: Fmt.temperature(celsius, fahrenheit: fahrenheit, decimals: 1), color: color)
            TileMeter(fraction: TemperatureScale.fraction(celsius), color: color)
            PerfGraph(
                series: [GraphSeries(values: history, color: color)],
                maxValue: max(60, (history.max() ?? 0) + 5),
                tint: color.opacity(0.6),
                showGrid: false
            )
            .frame(height: 44)
            TileNote(text: fromGasGauge ? "Measured by the battery" : "Average of the battery sensors", tertiary: true)
        }
    }
}

private struct AdapterCard: View {
    let battery: BatterySnapshot

    var body: some View {
        BatteryTile(symbol: "powerplug", title: "Power adapter") {
            if let adapter = battery.adapter {
                TileValue(value: adapter.watts.map { "\(Int($0.rounded())) W" } ?? "—", caption: adapter.isWireless ? "Wireless" : "Connected")
                TileNote(text: adapter.name)
                if let voltage = adapter.voltage, let current = adapter.current {
                    TileNote(text: String(format: "%.0f V · %.2f A", voltage, current), tertiary: true)
                }
                if let input = battery.adapterPower {
                    TileNote(text: "Supplying \(Fmt.watts(input)) now", tertiary: true)
                }
            } else if battery.externalConnected {
                TileValue(value: "Connected", caption: "")
                TileNote(text: "macOS doesn't report this adapter's details")
            } else {
                TileValue(value: "Not connected", color: Fluent.textSecondary)
                TileNote(text: "Running on battery power")
            }
        }
    }
}

private struct NoBatteryCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "powerplug")
                .font(.system(size: 22))
                .foregroundStyle(Fluent.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text("This Mac has no battery")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Fluent.textPrimary)
                Text("It runs on mains power. Battery usage by app still shows how much power each app uses, and what is keeping the Mac awake.")
                    .font(.system(size: 12))
                    .foregroundStyle(Fluent.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).fill(Fluent.card))
        .overlay(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).strokeBorder(Fluent.cardStroke))
    }
}

private struct SectionTitle: View {
    let title: String
    var detail = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Fluent.textPrimary)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Fluent.textSecondary)
                .lineLimit(1)
        }
    }
}

/// A rounded card around a list or chart.
private struct SectionCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).fill(Fluent.card))
            .overlay(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).strokeBorder(Fluent.cardStroke))
            .clipShape(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous))
    }
}

// MARK: - Last 24 hours

private struct BatteryHistoryChart: View {
    let points: [BatteryLog.Point]
    @State private var metric = Metric.level
    @State private var selection: Date?

    enum Metric: String, CaseIterable, Identifiable {
        case level, power
        var id: String { rawValue }
        var title: String { self == .level ? "Battery level" : "Power draw" }
    }

    struct Bucket: Identifiable {
        let start: Date
        let charge: Double      // percent
        let pluggedIn: Bool
        let power: Double?
        var id: Date { start }
    }

    private static let bucketLength: TimeInterval = 15 * 60

    var body: some View {
        let end = Self.bucketStart(Date()).addingTimeInterval(Self.bucketLength)
        let start = end.addingTimeInterval(-BatteryLog.span)
        let buckets = Self.buckets(points, from: start)
        let shown = metric == .level ? buckets : buckets.filter { $0.power != nil }
        let selected = selection.flatMap { date in buckets.first { $0.start == Self.bucketStart(date) } }
        let peak = Fmt.niceCeiling(buckets.compactMap(\.power).max() ?? 0, minimum: 10)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionTitle(title: "Last 24 hours", detail: "Recorded while Task Manager is running")
                Spacer()
                Picker("Chart", selection: $metric) {
                    ForEach(Metric.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            SectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        Text(readout(selected))
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(selected == nil ? Fluent.textSecondary : Fluent.textPrimary)
                        Spacer()
                        if metric == .level {
                            LegendSwatch(color: ChargeScale.onBattery, title: "On battery")
                            LegendSwatch(color: Fluent.efficiency, title: "Plugged in")
                        }
                    }
                    if shown.isEmpty {
                        Text(metric == .level
                             ? "The battery level appears here a minute after Task Manager starts recording."
                             : "This Mac hasn't reported its power draw yet.")
                            .font(.system(size: 12))
                            .foregroundStyle(Fluent.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 150)
                    } else {
                        chart(shown, start: start, end: end, peak: peak, selected: selected?.start)
                            .frame(height: 150)
                    }
                }
                .padding(14)
            }
        }
    }

    private func chart(_ buckets: [Bucket], start: Date, end: Date, peak: Double, selected: Date?) -> some View {
        let gap = Self.bucketLength * 0.12
        let top = metric == .level ? 100 : peak
        return Chart(buckets) { bucket in
            RectangleMark(
                xStart: .value("Start", bucket.start.addingTimeInterval(gap)),
                xEnd: .value("End", bucket.start.addingTimeInterval(Self.bucketLength - gap)),
                yStart: .value("Base", 0),
                yEnd: .value(metric.title, metric == .level ? bucket.charge : bucket.power ?? 0)
            )
            .cornerRadius(2)
            .foregroundStyle(metric == .power ? Fluent.accent : (bucket.pluggedIn ? Fluent.efficiency : ChargeScale.onBattery))
            .opacity(selected == nil || selected == bucket.start ? 1 : 0.4)
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...top)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine().foregroundStyle(Fluent.divider)
                AxisValueLabel(format: .dateTime.hour()).foregroundStyle(Fluent.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, top / 2, top]) { value in
                AxisGridLine().foregroundStyle(Fluent.divider)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(metric == .level ? "\(Int(v))%" : (v == v.rounded() ? "\(Int(v)) W" : Fmt.watts(v)))
                            .foregroundStyle(Fluent.textSecondary)
                    }
                }
            }
        }
        .chartXSelection(value: $selection)
    }

    private func readout(_ bucket: Bucket?) -> String {
        guard let bucket else {
            return metric == .level ? "Battery level every 15 minutes. Hover over a bar for details." : "Average power draw every 15 minutes."
        }
        let time = "\(bucket.start.formatted(date: .omitted, time: .shortened))–\(bucket.start.addingTimeInterval(Self.bucketLength).formatted(date: .omitted, time: .shortened))"
        let power = bucket.power.map { "average draw \(Fmt.watts($0))" } ?? "power draw not recorded"
        return "\(time) · \(Int(bucket.charge.rounded()))% · \(bucket.pluggedIn ? "plugged in" : "on battery") · \(power)"
    }

    private static func bucketStart(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / bucketLength).rounded(.down) * bucketLength)
    }

    /// The level at the end of each 15 minutes, whether the Mac was mostly plugged in, and the average draw.
    private static func buckets(_ points: [BatteryLog.Point], from start: Date) -> [Bucket] {
        let grouped = Dictionary(grouping: points.filter { $0.time >= start }, by: { bucketStart($0.time) })
        return grouped.keys.sorted().compactMap { key in
            guard let members = grouped[key]?.sorted(by: { $0.time < $1.time }), let last = members.last else { return nil }
            let powers = members.compactMap(\.power)
            return Bucket(
                start: key,
                charge: last.charge * 100,
                pluggedIn: members.filter(\.pluggedIn).count * 2 >= members.count,
                power: powers.isEmpty ? nil : powers.reduce(0, +) / Double(powers.count)
            )
        }
    }
}

private struct LegendSwatch: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(title).font(.system(size: 11.5)).foregroundStyle(Fluent.textSecondary)
        }
    }
}

// MARK: - Battery usage by app

private struct BatteryUsageList: View {
    let nodes: [ProcNode]
    let history: AppHistoryStore
    let assertions: [SleepAssertion]
    let energyAvailable: Bool
    @State private var sort = Column.power
    @State private var showAll = false

    enum Column { case name, power, trend, energy, wakeups, sleep }

    private static let collapsedCount = 12

    var body: some View {
        let awake = Dictionary(grouping: assertions, by: \.pid)
        let rows = sorted(nodes, awake: awake)
        let visible = showAll ? rows : Array(rows.prefix(Self.collapsedCount))
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(
                    title: "Battery usage by app",
                    detail: energyAvailable
                        ? "Energy used since \(history.since.formatted(date: .numeric, time: .omitted))"
                        : "Estimated from CPU use: this Mac doesn't report energy per app"
                )
                Spacer()
                if rows.count > Self.collapsedCount {
                    Button(showAll ? "Show fewer" : "Show all \(rows.count)") { showAll.toggle() }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
            }
            SectionCard {
                HStack(spacing: 0) {
                    header("Name", .name).frame(maxWidth: .infinity, alignment: .leading)
                    header(energyAvailable ? "Power" : "Power usage", .power).frame(width: 96, alignment: .trailing)
                    header("Power usage trend", .trend).frame(width: 128, alignment: .leading).padding(.leading, 12)
                    if energyAvailable {
                        header("Energy used", .energy).frame(width: 92, alignment: .trailing)
                    }
                    header("Idle wake-ups", .wakeups).frame(width: 100, alignment: .trailing)
                    header("Preventing sleep", .sleep).frame(width: 118, alignment: .leading).padding(.leading, 14)
                }
                .padding(.horizontal, 12)
                .frame(height: 30)
                Rectangle().fill(Fluent.divider).frame(height: 1)
                if visible.isEmpty {
                    Text("No matching apps")
                        .font(.system(size: 12))
                        .foregroundStyle(Fluent.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                ForEach(visible, id: \.id) { node in
                    UsageRow(
                        node: node,
                        energy: history.entries[node.historyKey]?.energy ?? 0,
                        assertions: node.pids.flatMap { awake[$0] ?? [] },
                        energyAvailable: energyAvailable
                    )
                }
            }
        }
    }

    private func header(_ title: String, _ column: Column) -> some View {
        Button {
            sort = column
        } label: {
            HStack(spacing: 4) {
                Text(title).lineLimit(1)
                if sort == column {
                    Image(systemName: column == .name ? "chevron.up" : "chevron.down").font(.system(size: 7, weight: .bold))
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Fluent.textSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sorted(_ nodes: [ProcNode], awake: [Int32: [SleepAssertion]]) -> [ProcNode] {
        func key(_ node: ProcNode) -> (Double, Double) {
            switch sort {
            case .name: return (0, 0)
            case .power: return (node.power, node.cpu)
            case .trend: return (node.powerTrend, node.cpuTrend)
            case .energy: return (history.entries[node.historyKey]?.energy ?? 0, node.power)
            case .wakeups: return (node.idleWakeups, node.power)
            case .sleep: return (node.pids.contains { awake[$0] != nil } ? 1 : 0, node.power)
            }
        }
        if sort == .name {
            return nodes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return nodes.sorted { a, b in
            let (ka, kb) = (key(a), key(b))
            if ka != kb { return ka > kb }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}

private struct UsageRow: View {
    let node: ProcNode
    let energy: Double
    let assertions: [SleepAssertion]
    let energyAvailable: Bool
    @State private var hovering = false

    var body: some View {
        let restricted = node.main?.restricted ?? false
        let usage = ProcessRows.powerUsage(watts: node.power, cpu: node.cpu, restricted: restricted)
        let trend = ProcessRows.powerUsage(watts: node.powerTrend, cpu: node.cpuTrend, restricted: restricted)
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                ProcessIcon(path: node.iconPath, symbol: node.iconPath == nil ? "cpu" : nil)
                    .frame(width: 16, height: 16)
                Text(node.name).lineLimit(1).truncationMode(.tail)
                if node.members.count > 1 {
                    Text("(\(node.members.count))").foregroundStyle(Fluent.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(energyAvailable && !restricted ? Fmt.watts(node.power) : usage.title)
                .monospacedDigit()
                .padding(.horizontal, 8)
                .frame(width: 96, height: 28, alignment: .trailing)
                .background(Heat.color(usage.heat))
                .help(usage.title)
            Text(trend.title)
                .foregroundStyle(Fluent.textSecondary)
                .frame(width: 128, alignment: .leading)
                .padding(.leading, 12)
            if energyAvailable {
                Text(energy > 0 ? Fmt.energy(energy) : "")
                    .monospacedDigit()
                    .frame(width: 92, alignment: .trailing)
            }
            Text(restricted ? "" : node.idleWakeups >= 0.5 ? "\(Int(node.idleWakeups.rounded()))/s" : "0/s")
                .monospacedDigit()
                .foregroundStyle(Fluent.textSecondary)
                .frame(width: 100, alignment: .trailing)
            HStack(spacing: 5) {
                if !assertions.isEmpty {
                    Image(systemName: assertions.contains(where: \.preventsDisplaySleep) ? "display" : "moon.zzz")
                        .foregroundStyle(Fluent.accent)
                    Text("Yes")
                }
            }
            .frame(width: 118, alignment: .leading)
            .padding(.leading, 14)
            .help(assertions.map { $0.reason.isEmpty ? $0.processName : $0.reason }.joined(separator: "\n"))
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Fluent.textPrimary)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(hovering ? Fluent.rowHover : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            ProcessRowMenu(row: menuRow, toggle: { _ in })
        }
    }

    private var menuRow: HeatRow {
        var row = ProcessRows.row(for: node, expanded: false)
        row.isExpandable = false
        return row
    }
}

// MARK: - Preventing sleep

private struct SleepAssertionList: View {
    let assertions: [SleepAssertion]
    let nodes: [ProcNode]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: "Preventing sleep", detail: assertions.isEmpty ? "" : "\(assertions.count)")
            SectionCard {
                if assertions.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "moon.zzz").foregroundStyle(Fluent.accent)
                        Text("Nothing is keeping your Mac awake. It can sleep when idle.")
                            .foregroundStyle(Fluent.textSecondary)
                        Spacer()
                    }
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                } else {
                    ForEach(Array(assertions.enumerated()), id: \.element.id) { index, assertion in
                        if index > 0 { Rectangle().fill(Fluent.divider).frame(height: 1) }
                        row(assertion)
                    }
                }
            }
        }
    }

    private func row(_ assertion: SleepAssertion) -> some View {
        let node = nodes.first { $0.pids.contains(assertion.pid) }
        return HStack(spacing: 10) {
            ProcessIcon(path: node?.iconPath, symbol: node?.iconPath == nil ? "gearshape" : nil)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(node?.name ?? assertion.processName)
                    .foregroundStyle(Fluent.textPrimary)
                Text(assertion.reason.isEmpty ? assertion.processName : assertion.reason)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Fluent.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(assertion.reason)
            }
            Spacer(minLength: 12)
            Label(assertion.preventsDisplaySleep ? "Keeps the display on" : "Prevents sleep",
                  systemImage: assertion.preventsDisplaySleep ? "display" : "moon.zzz")
                .foregroundStyle(Fluent.textSecondary)
                .frame(width: 170, alignment: .leading)
            Text(assertion.since.map(Self.since) ?? "")
                .monospacedDigit()
                .foregroundStyle(Fluent.textTertiary)
                .frame(width: 110, alignment: .trailing)
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private static func since(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? "Since \(date.formatted(date: .omitted, time: .shortened))"
            : "Since \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

// MARK: - Details

private struct BatteryDetails: View {
    let battery: BatterySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: "Battery information")
            SectionCard {
                HStack(alignment: .top, spacing: 40) {
                    KeyValueGrid(rows: batteryRows)
                    KeyValueGrid(rows: powerRows)
                    Spacer(minLength: 0)
                }
                .padding(14)
            }
        }
    }

    private var batteryRows: [(String, String)] {
        var rows: [(String, String)] = []
        rows.append(("Condition", battery.condition ?? "Unknown"))
        if let health = battery.health { rows.append(("Maximum capacity", Fmt.wholePercent(health))) }
        if let cycles = battery.cycleCount { rows.append(("Cycle count", cycles.formatted())) }
        if let full = battery.fullChargeCapacity { rows.append(("Full charge capacity", Fmt.milliampHours(full))) }
        if let design = battery.designCapacity { rows.append(("Design capacity", Fmt.milliampHours(design))) }
        if let remaining = battery.remainingCapacity { rows.append(("Remaining charge", Fmt.milliampHours(remaining))) }
        if let serial = battery.serial { rows.append(("Serial number", serial)) }
        if let device = battery.deviceName { rows.append(("Device name", device)) }
        if let manufacturer = battery.manufacturer { rows.append(("Manufacturer", manufacturer)) }
        return rows
    }

    private var powerRows: [(String, String)] {
        var rows: [(String, String)] = []
        rows.append(("Power source", battery.externalConnected ? "Power adapter" : "Battery"))
        if let voltage = battery.voltage { rows.append(("Voltage", String(format: "%.2f V", voltage))) }
        if let amperage = battery.amperage { rows.append(("Current", "\(Int((amperage * 1000).rounded()).formatted()) mA")) }
        if let flow = battery.batteryPower {
            let direction = flow > 0.05 ? "into the battery" : (flow < -0.05 ? "out of the battery" : "")
            rows.append(("Battery power", direction.isEmpty ? Fmt.watts(0) : "\(Fmt.watts(flow)) \(direction)"))
        }
        if !battery.cellVoltages.isEmpty {
            rows.append(("Cell voltages", battery.cellVoltages.map { String(format: "%.3f V", $0) }.joined(separator: ", ")))
        }
        rows.append(("Low Power Mode", battery.lowPowerMode ? "On" : "Off"))
        if battery.optimizedCharging { rows.append(("Optimized charging", "Holding the charge")) }
        if let adapter = battery.adapter {
            rows.append(("Adapter", adapter.name))
            if let manufacturer = adapter.manufacturer { rows.append(("Adapter maker", manufacturer)) }
        }
        return rows
    }
}
