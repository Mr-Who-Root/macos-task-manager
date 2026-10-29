import SwiftUI
import TaskManagerShared
import WidgetKit

/// Widgets that mix several resources.
struct OverviewWidgets: WidgetBundle {
    var body: some Widget {
        GlanceWidget()
        PerformanceGraphsWidget()
        DashboardWidget()
    }
}

// MARK: - Widget definitions

struct GPUWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GPUWidget", provider: StatsProvider()) { GPUWidgetView(entry: $0) }
            .configurationDisplayName("GPU")
            .description("Graphics processor usage with a live graph.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct GlanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GlanceWidget", provider: StatsProvider()) { GlanceWidgetView(entry: $0) }
            .configurationDisplayName("At a Glance")
            .description("CPU, memory, battery and temperature in one small widget.")
            .supportedFamilies([.systemSmall])
    }
}

struct PerformanceGraphsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PerformanceGraphsWidget", provider: StatsProvider()) { PerformanceGraphsWidgetView(entry: $0) }
            .configurationDisplayName("Performance")
            .description("Live graphs for CPU, memory, GPU and network, plus disk and power on the large size.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct DashboardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DashboardWidget", provider: StatsProvider()) { DashboardWidgetView(entry: $0) }
            .configurationDisplayName("Dashboard")
            .description("Everything at once: resources, battery, temperatures, network and the busiest apps.")
            .supportedFamilies([.systemLarge, .systemExtraLarge])
    }
}

// MARK: - Building blocks

/// A small ring with its value inside and a label underneath.
struct MiniGauge: View {
    let label: String
    let value: String
    let fraction: Double
    let color: Color
    let theme: WidgetTheme
    var size: CGFloat = 44

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Ring(fraction: fraction, color: color, track: theme.track, lineWidth: 5)
                Text(value).font(.system(size: 11.5, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.horizontal, 6)
            }
            .frame(width: size, height: size)
            Text(label).font(.system(size: 9.5)).foregroundStyle(theme.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A titled tile with a value and a sparkline, like the Performance page's list.
struct GraphTile: View {
    let title: String
    let value: String
    let values: [Double]
    let maxValue: Double
    let color: Color
    let theme: WidgetTheme
    var secondary: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title).font(.system(size: 10.5)).foregroundStyle(theme.secondary).lineLimit(1)
                Spacer(minLength: 2)
                Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
            if values.count > 1 {
                ZStack {
                    Sparkline(values: values, maxValue: maxValue, color: color)
                    if secondary.count > 1 {
                        Sparkline(values: secondary, maxValue: maxValue, color: color.opacity(0.6), filled: false)
                    }
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.track.opacity(0.55)))
    }
}

/// CPU, memory, GPU and disk rings in a row.
struct ResourceRings: View {
    let snapshot: WidgetSnapshot
    let theme: WidgetTheme
    var lineWidth: CGFloat = 7

    var body: some View {
        let s = snapshot
        let metrics: [(String, Double, Color)] = [
            ("CPU", s.cpu, theme.cpu),
            ("Memory", s.memoryFraction, theme.memory),
            ("GPU", s.gpu ?? 0, theme.gpu),
            ("Disk", s.diskUsedFraction, theme.disk),
        ]
        HStack(spacing: 10) {
            ForEach(metrics, id: \.0) { metric in
                VStack(spacing: 4) {
                    ZStack {
                        Ring(fraction: metric.1, color: metric.2, track: theme.track, lineWidth: lineWidth)
                        Text(metric.0 == "GPU" && s.gpu == nil ? "—" : WFmt.percent(metric.1))
                            .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    }
                    Text(metric.0).font(.system(size: 10.5)).foregroundStyle(theme.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// The temperatures the app shares, as a row of chips.
struct TemperatureChips: View {
    let snapshot: WidgetSnapshot
    let theme: WidgetTheme
    var count = 4

    var body: some View {
        // One per kind: P-cores, E-cores and CPU share an icon, so only the first (hottest-ranked) shows.
        var seen = Set<String>()
        let kinds = snapshot.temperatures.filter { seen.insert($0.symbol).inserted }
        HStack(spacing: 8) {
            ForEach(Array(kinds.prefix(count).enumerated()), id: \.offset) { _, temp in
                HStack(spacing: 4) {
                    Image(systemName: temp.symbol).font(.system(size: 10)).foregroundStyle(theme.secondary)
                    Text(WFmt.temperature(temp.celsius, fahrenheit: snapshot.fahrenheit))
                        .font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(theme.temperature(temp.celsius))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

extension WidgetSnapshot {
    /// The graph tiles shared by the Performance and Dashboard widgets.
    func tile(_ kind: String, _ theme: WidgetTheme) -> GraphTile {
        switch kind {
        case "memory":
            return GraphTile(title: "Memory", value: WFmt.percent(memoryFraction), values: memoryHistory, maxValue: 1, color: theme.memory, theme: theme)
        case "gpu":
            return GraphTile(title: "GPU", value: gpu.map(WFmt.percent) ?? "—", values: gpuHistory, maxValue: 1, color: theme.gpu, theme: theme)
        case "network":
            let scale = max((networkReceiveHistory + networkSendHistory).max() ?? 0, 102_400)
            return GraphTile(title: "Network", value: "↓ \(WFmt.rate(networkReceive))", values: networkReceiveHistory, maxValue: scale,
                             color: theme.network, theme: theme, secondary: networkSendHistory)
        case "disk":
            let read = diskReadHistory ?? [], write = diskWriteHistory ?? []
            let scale = max((read + write).max() ?? 0, 1_048_576)
            return GraphTile(title: "Disk", value: WFmt.rate(diskRead + diskWrite), values: read, maxValue: scale,
                             color: theme.disk, theme: theme, secondary: write)
        case "power":
            let history = battery?.powerHistory ?? []
            let peak = max(history.max() ?? 0, 10)
            return GraphTile(title: "Power", value: battery?.powerDraw.map(WFmt.watts) ?? "—", values: history,
                             maxValue: [10.0, 20, 30, 50, 75, 100, 150, 200].first { $0 >= peak } ?? peak, color: theme.power, theme: theme)
        default:
            return GraphTile(title: "CPU", value: WFmt.percent(cpu), values: cpuHistory, maxValue: 1, color: theme.cpu, theme: theme)
        }
    }
}

// MARK: - GPU

struct GPUWidgetView: View {
    let entry: StatsEntry
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.widgetFamilyOverride) private var familyOverride
    private var family: WidgetFamily { familyOverride ?? systemFamily }

    var body: some View {
        let s = entry.snapshot
        WidgetShell(entry: entry, link: "performance/gpu") { theme in
            if let gpu = s.gpu {
                let ring = ZStack {
                    Ring(fraction: gpu, color: theme.gpu, track: theme.track, lineWidth: 10)
                    Text(WFmt.percent(gpu)).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                }
                let name = s.gpuCores.map { "\($0)-core GPU" } ?? s.gpuName
                if family == .systemMedium {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            WidgetHeader(symbol: "cube.transparent", title: "GPU", tint: theme.gpu, theme: theme)
                            ring
                        }
                        .frame(width: 112)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(s.gpuName).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            if s.gpuHistory.count > 1 {
                                Sparkline(values: s.gpuHistory, maxValue: 1, color: theme.gpu).frame(maxHeight: .infinity)
                            } else {
                                Spacer(minLength: 0)
                            }
                            Text(s.gpuCores.map { "\($0) cores · last minute" } ?? "Last minute")
                                .font(.system(size: 10.5)).foregroundStyle(theme.secondary).lineLimit(1)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        WidgetHeader(symbol: "cube.transparent", title: "GPU", tint: theme.gpu, theme: theme)
                        ring
                        Text(name).font(.system(size: 10.5)).foregroundStyle(theme.secondary).lineLimit(1).frame(maxWidth: .infinity)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeader(symbol: "cube.transparent", title: "GPU", tint: theme.gpu, theme: theme)
                    NeedsAppNote(text: "Open Task Manager to measure the GPU.", theme: theme)
                }
            }
        }
    }
}

// MARK: - At a glance

struct GlanceWidgetView: View {
    let entry: StatsEntry

    var body: some View {
        let s = entry.snapshot
        WidgetShell(entry: entry, link: "performance") { theme in
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(symbol: "square.grid.2x2.fill", title: "At a glance", tint: theme.accent(s.accent), theme: theme)
                Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                    GridRow {
                        MiniGauge(label: "CPU", value: WFmt.percent(s.cpu), fraction: s.cpu, color: theme.cpu, theme: theme)
                        MiniGauge(label: "Memory", value: WFmt.percent(s.memoryFraction), fraction: s.memoryFraction, color: theme.memory, theme: theme)
                    }
                    GridRow {
                        if let battery = s.battery {
                            MiniGauge(label: battery.isCharging ? "Charging" : "Battery", value: WFmt.percent(battery.charge),
                                      fraction: battery.charge, color: theme.charge(battery), theme: theme)
                        } else if let gpu = s.gpu {
                            MiniGauge(label: "GPU", value: WFmt.percent(gpu), fraction: gpu, color: theme.gpu, theme: theme)
                        } else {
                            MiniGauge(label: "Disk", value: WFmt.percent(s.diskUsedFraction), fraction: s.diskUsedFraction, color: theme.disk, theme: theme)
                        }
                        if let temp = s.temperatures.first {
                            MiniGauge(label: "\(temp.name) temp", value: WFmt.temperature(temp.celsius, fahrenheit: s.fahrenheit),
                                      fraction: (temp.celsius - 20) / 90, color: theme.temperature(temp.celsius), theme: theme)
                        } else {
                            MiniGauge(label: "Disk", value: WFmt.percent(s.diskUsedFraction), fraction: s.diskUsedFraction, color: theme.disk, theme: theme)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Performance graphs

struct PerformanceGraphsWidgetView: View {
    let entry: StatsEntry
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.widgetFamilyOverride) private var familyOverride
    private var family: WidgetFamily { familyOverride ?? systemFamily }

    var body: some View {
        let s = entry.snapshot
        WidgetShell(entry: entry, link: "performance") { theme in
            let large = family == .systemLarge
            let kinds = large ? ["cpu", "memory", "gpu", "network", "disk", s.battery?.powerDraw != nil ? "power" : "disk"] : ["cpu", "memory", "gpu", "network"]
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    WidgetHeader(symbol: "waveform.path.ecg", title: "Performance", tint: theme.accent(s.accent), theme: theme)
                    Text("Up \(WFmt.uptime(s.uptime))").font(.system(size: 10.5)).foregroundStyle(theme.secondary).fixedSize()
                }
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(0..<(kinds.count / 2), id: \.self) { row in
                        GridRow {
                            s.tile(kinds[row * 2], theme)
                            s.tile(kinds[row * 2 + 1], theme)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Dashboard

struct DashboardWidgetView: View {
    let entry: StatsEntry
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.widgetFamilyOverride) private var familyOverride
    private var family: WidgetFamily { familyOverride ?? systemFamily }

    var body: some View {
        let s = entry.snapshot
        WidgetShell(entry: entry, link: "performance") { theme in
            if family == .systemExtraLarge {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        header(s, theme)
                        ResourceRings(snapshot: s, theme: theme, lineWidth: 8).frame(height: 78)
                        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                            GridRow {
                                s.tile("cpu", theme)
                                s.tile("memory", theme)
                            }
                            GridRow {
                                s.tile("network", theme)
                                s.tile(s.battery?.powerDraw != nil ? "power" : "disk", theme)
                            }
                        }
                    }
                    Rectangle().fill(theme.track).frame(width: 1)
                    VStack(alignment: .leading, spacing: 10) {
                        if let battery = s.battery {
                            batteryBlock(battery, theme)
                        }
                        if entry.isLive && !s.temperatures.isEmpty {
                            TemperatureChips(snapshot: s, theme: theme)
                        }
                        Divider().overlay(theme.track)
                        apps(s, theme, count: s.battery == nil ? 7 : 4)
                    }
                    .frame(width: 320)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    header(s, theme)
                    ResourceRings(snapshot: s, theme: theme)
                    HStack(spacing: 8) {
                        s.tile("network", theme)
                        if let battery = s.battery {
                            compactBattery(battery, theme)
                        } else {
                            s.tile("disk", theme)
                        }
                    }
                    .frame(height: 70)
                    if entry.isLive && !s.temperatures.isEmpty {
                        TemperatureChips(snapshot: s, theme: theme)
                    }
                    Divider().overlay(theme.track)
                    apps(s, theme, count: 3)
                }
            }
        }
    }

    private func header(_ s: WidgetSnapshot, _ theme: WidgetTheme) -> some View {
        HStack {
            WidgetHeader(symbol: "gauge.with.dots.needle.67percent", title: "Task Manager", tint: theme.accent(s.accent), theme: theme)
            Text(s.processCount > 0 ? "\(s.processCount) processes · Up \(WFmt.uptime(s.uptime))" : "Up \(WFmt.uptime(s.uptime))")
                .font(.system(size: 10.5)).foregroundStyle(theme.secondary).fixedSize()
        }
    }

    private func compactBattery(_ battery: WidgetSnapshot.Battery, _ theme: WidgetTheme) -> some View {
        HStack(spacing: 8) {
            ChargeRing(battery: battery, theme: theme, lineWidth: 6, fontSize: 13).frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 1) {
                Text("Battery").font(.system(size: 10.5)).foregroundStyle(theme.secondary)
                Text(battery.shortTimeText).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                if let draw = battery.powerDraw {
                    Text("Using \(WFmt.watts(draw))").font(.system(size: 10.5)).foregroundStyle(theme.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.track.opacity(0.55)))
    }

    private func batteryBlock(_ battery: WidgetSnapshot.Battery, _ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                ChargeRing(battery: battery, theme: theme, lineWidth: 8, fontSize: 17).frame(width: 70, height: 70)
                VStack(alignment: .leading, spacing: 2) {
                    WidgetHeader(symbol: battery.symbol, title: "Battery", tint: theme.charge(battery), theme: theme)
                    Text(battery.status).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Text(battery.timeText).font(.system(size: 10.5)).foregroundStyle(theme.secondary).lineLimit(1)
                    HStack(spacing: 10) {
                        if let draw = battery.powerDraw { StatChip(symbol: "bolt.fill", value: WFmt.watts(draw), tint: theme.power) }
                        if let health = battery.health {
                            StatChip(symbol: "heart.fill", value: WFmt.percent(health), tint: battery.isHealthy ? theme.good : theme.critical)
                        }
                    }
                }
            }
            if !battery.levels.isEmpty {
                LevelBars(levels: battery.levels, now: entry.date, theme: theme).frame(height: 30)
            }
        }
    }

    @ViewBuilder
    private func apps(_ s: WidgetSnapshot, _ theme: WidgetTheme, count: Int) -> some View {
        if entry.isLive && !s.topApps.isEmpty {
            AppRows(apps: Array(s.topApps.prefix(count)), theme: theme, compact: true)
            Spacer(minLength: 0)
            if let blockers = s.sleepBlockers, !blockers.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "moon.zzz").font(.system(size: 10))
                    Text("Keeping your Mac awake: \(blockers.map(\.name).joined(separator: ", "))").font(.system(size: 10.5)).lineLimit(1)
                }
                .foregroundStyle(theme.secondary)
            }
        } else {
            NeedsAppNote(text: "Open Task Manager to see the busiest apps.", theme: theme)
        }
    }
}
