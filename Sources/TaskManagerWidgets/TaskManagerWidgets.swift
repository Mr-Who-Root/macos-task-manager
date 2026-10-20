import SwiftUI
import TaskManagerShared
import WidgetKit

@main
struct TaskManagerWidgetBundle: WidgetBundle {
    var body: some Widget {
        CPUWidget()
        MemoryWidget()
        SystemWidget()
        TopAppsWidget()
        TemperatureWidget()
        NetworkWidget()
        StorageWidget()
    }
}

// MARK: - Widget definitions

struct CPUWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CPUWidget", provider: StatsProvider()) { CPUWidgetView(entry: $0) }
            .configurationDisplayName("CPU")
            .description("Processor usage with a live graph and every core.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MemoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MemoryWidget", provider: StatsProvider()) { MemoryWidgetView(entry: $0) }
            .configurationDisplayName("Memory")
            .description("Memory in use, compressed, cached and swap.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SystemWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SystemWidget", provider: StatsProvider()) { SystemWidgetView(entry: $0) }
            .configurationDisplayName("System")
            .description("CPU, memory, GPU and disk at a glance, plus the busiest apps on the large size.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TopAppsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TopAppsWidget", provider: StatsProvider()) { TopAppsWidgetView(entry: $0) }
            .configurationDisplayName("Top Apps")
            .description("The apps using the most CPU, with Task Manager's heat map.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TemperatureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TemperatureWidget", provider: StatsProvider()) { TemperatureWidgetView(entry: $0) }
            .configurationDisplayName("Temperatures")
            .description("CPU, GPU, SSD and battery temperatures and fan speed.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NetworkWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NetworkWidget", provider: StatsProvider()) { NetworkWidgetView(entry: $0) }
            .configurationDisplayName("Network")
            .description("Upload and download speed.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StorageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StorageWidget", provider: StatsProvider()) { StorageWidgetView(entry: $0) }
            .configurationDisplayName("Storage")
            .description("Free space on your startup disk.")
            .supportedFamilies([.systemSmall])
    }
}

// MARK: - Formatting

enum WFmt {
    static func percent(_ fraction: Double) -> String { "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%" }

    static func gigabytes(_ bytes: UInt64) -> String { String(format: "%.1f GB", Double(bytes) / 1_073_741_824) }

    static func storage(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        return gb >= 1_000 ? String(format: "%.1f TB", gb / 1_000) : String(format: "%.0f GB", gb)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let v = max(bytesPerSecond, 0)
        if v < 1_024 { return "0 KB/s" }
        if v < 1_048_576 { return String(format: "%.0f KB/s", v / 1_024) }
        return String(format: "%.1f MB/s", v / 1_048_576)
    }

    static func temperature(_ celsius: Double, fahrenheit: Bool) -> String {
        "\(Int((fahrenheit ? celsius * 9 / 5 + 32 : celsius).rounded()))°"
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let t = Int(seconds)
        let days = t / 86_400, hours = (t % 86_400) / 3_600, minutes = (t % 3_600) / 60
        return days > 0 ? "\(days)d \(hours)h" : "\(hours)h \(minutes)m"
    }
}

// MARK: - Building blocks

private struct WidgetFamilyOverrideKey: EnvironmentKey {
    static let defaultValue: WidgetFamily? = nil
}

extension EnvironmentValues {
    /// Lets previews render a specific size (WidgetKit's own `widgetFamily` is read-only).
    var widgetFamilyOverride: WidgetFamily? {
        get { self[WidgetFamilyOverrideKey.self] }
        set { self[WidgetFamilyOverrideKey.self] = newValue }
    }
}

/// Applies the design's background, font and tap destination.
struct WidgetShell<Content: View>: View {
    let entry: StatsEntry
    let link: String
    @ViewBuilder var content: (WidgetTheme) -> Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = WidgetTheme(design: entry.snapshot.design, scheme: scheme)
        content(theme)
            .foregroundStyle(theme.primary)
            .fontDesign(theme.fontDesign)
            .containerBackground(for: .widget) { theme.background }
            .widgetURL(URL(string: "\(WidgetSnapshotStore.urlScheme)://\(link)"))
    }
}

struct WidgetHeader: View {
    let symbol: String
    let title: String
    let tint: Color
    let theme: WidgetTheme

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.secondary)
            Spacer(minLength: 0)
        }
    }
}

struct Ring: View {
    let fraction: Double
    let color: Color
    let track: Color
    var lineWidth: CGFloat = 9

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0.004), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}

struct Sparkline: View {
    let values: [Double]
    let maxValue: Double
    let color: Color
    var filled = true

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height
            let points = values.suffix(60)
            let count = points.count
            if count > 1 {
                let scale = maxValue > 0 ? maxValue : 1
                let path = Path { p in
                    for (i, v) in points.enumerated() {
                        let point = CGPoint(x: w * CGFloat(i) / CGFloat(count - 1), y: h * (1 - CGFloat(min(max(v / scale, 0), 1))))
                        i == 0 ? p.move(to: point) : p.addLine(to: point)
                    }
                }
                if filled {
                    Path { p in
                        p.addPath(path)
                        p.addLine(to: CGPoint(x: w, y: h))
                        p.addLine(to: CGPoint(x: 0, y: h))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                }
                path.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
    }
}

struct Meter: View {
    let fraction: Double
    let color: Color
    let track: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(color).frame(width: max(4, geometry.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 6)
    }
}

/// Shown on widgets that need Task Manager running (processes, sensors).
struct NeedsAppNote: View {
    let text: String
    let theme: WidgetTheme

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "macwindow.badge.plus").font(.system(size: 18)).foregroundStyle(theme.secondary)
            Text(text).font(.system(size: 11)).multilineTextAlignment(.center).foregroundStyle(theme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - CPU

struct CPUWidgetView: View {
    let entry: StatsEntry
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.widgetFamilyOverride) private var familyOverride
    private var family: WidgetFamily { familyOverride ?? systemFamily }

    var body: some View {
        let s = entry.snapshot
        WidgetShell(entry: entry, link: "performance/cpu") { theme in
            if family == .systemSmall {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeader(symbol: "cpu", title: "CPU", tint: theme.cpu, theme: theme)
                    ZStack {
                        Ring(fraction: s.cpu, color: theme.cpu, track: theme.track, lineWidth: 10)
                        Text(WFmt.percent(s.cpu)).font(.system(size: 24, weight: .semibold)).monospacedDigit()
                    }
                    Text("Up \(WFmt.uptime(s.uptime))").font(.system(size: 10.5)).foregroundStyle(theme.secondary)
                        .frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        WidgetHeader(symbol: "cpu", title: "CPU", tint: theme.cpu, theme: theme)
                        ZStack {
                            Ring(fraction: s.cpu, color: theme.cpu, track: theme.track, lineWidth: 10)
                            Text(WFmt.percent(s.cpu)).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                        }
                    }
                    .frame(width: 112)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.cpuName).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        if s.cpuHistory.count > 1 {
                            Sparkline(values: s.cpuHistory, maxValue: 1, color: theme.cpu).frame(height: 38)
                        }
                        if !s.perCore.isEmpty {
                            HStack(alignment: .bottom, spacing: 2) {
                                ForEach(Array(s.perCore.prefix(16).enumerated()), id: \.offset) { _, core in
                                    ZStack(alignment: .bottom) {
                                        RoundedRectangle(cornerRadius: 1.5).fill(theme.track)
                                        RoundedRectangle(cornerRadius: 1.5).fill(theme.cpu).frame(height: max(2, 22 * core))
                                    }
                                    .frame(height: 22)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        Text(s.processCount > 0 ? "\(s.processCount) processes · Up \(WFmt.uptime(s.uptime))" : "Up \(WFmt.uptime(s.uptime))")
                            .font(.system(size: 10.5)).foregroundStyle(theme.secondary).lineLimit(1)
                    }
                }
            }
        }
    }
}

// MARK: - Memory

struct MemoryWidgetView: View {
    let entry: StatsEntry
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.widgetFamilyOverride) private var familyOverride
    private var family: WidgetFamily { familyOverride ?? systemFamily }

    var body: some View {
        let s = entry.snapshot
        WidgetShell(entry: entry, link: "performance/memory") { theme in
            let ring = ZStack {
                Ring(fraction: s.memoryFraction, color: theme.memory, track: theme.track, lineWidth: 10)
                VStack(spacing: 0) {
                    Text(WFmt.percent(s.memoryFraction)).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                    Text("in use").font(.system(size: 9.5)).foregroundStyle(theme.secondary)
                }
            }
            if family == .systemSmall {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeader(symbol: "memorychip", title: "Memory", tint: theme.memory, theme: theme)
                    ring
                    Text("\(WFmt.gigabytes(s.memoryUsed)) of \(WFmt.gigabytes(s.memoryTotal))")
                        .font(.system(size: 10.5)).foregroundStyle(theme.secondary).frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        WidgetHeader(symbol: "memorychip", title: "Memory", tint: theme.memory, theme: theme)
                        ring
                    }
                    .frame(width: 112)
                    VStack(alignment: .leading, spacing: 5) {
                        row("In use", WFmt.gigabytes(s.memoryUsed), theme)
                        row("Compressed", WFmt.gigabytes(s.memoryCompressed), theme)
                        row("Cached", WFmt.gigabytes(s.memoryCached), theme)
                        if entry.isLive {
                            row("Swap", WFmt.gigabytes(s.swapUsed), theme)
                            row("Pressure", s.memoryPressure, theme)
                        }
                        if s.memoryHistory.count > 1 {
                            Sparkline(values: s.memoryHistory, maxValue: 1, color: theme.memory).frame(height: 22)
                        }
                    }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String, _ theme: WidgetTheme) -> some View {
        HStack {
            Text(label).foregroundStyle(theme.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.system(size: 11))
    }
}

// MARK: - System overview

struct SystemWidgetView: View {
    let entry: StatsEntry
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.widgetFamilyOverride) private var familyOverride
    private var family: WidgetFamily { familyOverride ?? systemFamily }

    var body: some View {
        let s = entry.snapshot
        WidgetShell(entry: entry, link: "performance") { theme in
            let metrics: [(String, String, Double, Color)] = [
                ("CPU", "cpu", s.cpu, theme.cpu),
                ("Memory", "memorychip", s.memoryFraction, theme.memory),
                ("GPU", "cube.transparent", s.gpu ?? 0, theme.gpu),
                ("Disk", "internaldrive", s.diskUsedFraction, theme.disk),
            ]
            switch family {
            case .systemSmall:
                VStack(alignment: .leading, spacing: 9) {
                    WidgetHeader(symbol: "gauge.with.dots.needle.67percent", title: "System", tint: theme.accent(s.accent), theme: theme)
                    ForEach(metrics, id: \.0) { metric in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(metric.0).font(.system(size: 11)).foregroundStyle(theme.secondary)
                                Spacer()
                                Text(WFmt.percent(metric.2)).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                            }
                            Meter(fraction: metric.2, color: metric.3, track: theme.track)
                        }
                    }
                }
            case .systemLarge:
                VStack(alignment: .leading, spacing: 12) {
                    WidgetHeader(symbol: "gauge.with.dots.needle.67percent", title: "System", tint: theme.accent(s.accent), theme: theme)
                    rings(metrics, theme)
                    Divider().overlay(theme.track)
                    if entry.isLive {
                        AppRows(apps: Array(s.topApps.prefix(4)), theme: theme, compact: true)
                        if !s.temperatures.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(Array(s.temperatures.prefix(4).enumerated()), id: \.offset) { _, temp in
                                    HStack(spacing: 4) {
                                        Image(systemName: temp.symbol).font(.system(size: 10)).foregroundStyle(theme.secondary)
                                        Text(WFmt.temperature(temp.celsius, fahrenheit: s.fahrenheit))
                                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.temperature(temp.celsius))
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    } else {
                        NeedsAppNote(text: "Open Task Manager to see the busiest apps and temperatures.", theme: theme)
                    }
                    Spacer(minLength: 0)
                }
            default:
                VStack(alignment: .leading, spacing: 8) {
                    WidgetHeader(symbol: "gauge.with.dots.needle.67percent", title: "System", tint: theme.accent(s.accent), theme: theme)
                    rings(metrics, theme)
                }
            }
        }
    }

    private func rings(_ metrics: [(String, String, Double, Color)], _ theme: WidgetTheme) -> some View {
        HStack(spacing: 10) {
            ForEach(metrics, id: \.0) { metric in
                VStack(spacing: 4) {
                    ZStack {
                        Ring(fraction: metric.2, color: metric.3, track: theme.track, lineWidth: 7)
                        Text(WFmt.percent(metric.2)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    }
                    Text(metric.0).font(.system(size: 10.5)).foregroundStyle(theme.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Top apps

struct AppRows: View {
    let apps: [WidgetSnapshot.App]
    let theme: WidgetTheme
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 3 : 4) {
            ForEach(Array(apps.enumerated()), id: \.offset) { _, app in
                HStack(spacing: 6) {
                    if let data = app.icon, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().frame(width: 16, height: 16)
                    } else {
                        RoundedRectangle(cornerRadius: 4).fill(theme.track).frame(width: 16, height: 16)
                    }
                    Text(app.name).font(.system(size: 11.5)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(String(format: "%.1f%%", app.cpu))
                        .font(.system(size: 11)).monospacedDigit()
                        .frame(width: 50, height: compact ? 18 : 20, alignment: .trailing)
                        .padding(.trailing, 4)
                        .background(theme.heat(app.cpu / 35))
                    Text(app.memory >= 1_073_741_824 ? String(format: "%.1f GB", Double(app.memory) / 1_073_741_824)
                                                      : String(format: "%.0f MB", Double(app.memory) / 1_048_576))
                        .font(.system(size: 11)).monospacedDigit()
                        .frame(width: 58, height: compact ? 18 : 20, alignment: .trailing)
                        .padding(.trailing, 4)
                        .background(theme.heat(Double(app.memory) / 4_000_000_000))
                }
            }
        }
    }
}

struct TopAppsWidgetView: View {
    let entry: StatsEntry
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.widgetFamilyOverride) private var familyOverride
    private var family: WidgetFamily { familyOverride ?? systemFamily }

    var body: some View {
        let s = entry.snapshot
        WidgetShell(entry: entry, link: "processes") { theme in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    WidgetHeader(symbol: "square.grid.2x2", title: "Top apps", tint: theme.accent(s.accent), theme: theme)
                    Text("CPU \(WFmt.percent(s.cpu))  ·  Memory \(WFmt.percent(s.memoryFraction))")
                        .font(.system(size: 10.5)).foregroundStyle(theme.secondary).fixedSize()
                }
                if entry.isLive && !s.topApps.isEmpty {
                    AppRows(apps: Array(s.topApps.prefix(family == .systemLarge ? 9 : 4)), theme: theme)
                    Spacer(minLength: 0)
                } else {
                    NeedsAppNote(text: "Open Task Manager to see which apps are busiest.", theme: theme)
                }
            }
        }
    }
}

// MARK: - Temperatures

struct TemperatureWidgetView: View {
    let entry: StatsEntry
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.widgetFamilyOverride) private var familyOverride
    private var family: WidgetFamily { familyOverride ?? systemFamily }

    var body: some View {
        let s = entry.snapshot
        WidgetShell(entry: entry, link: "temperatures") { theme in
            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(symbol: "thermometer.medium", title: "Temperatures", tint: theme.temperature(s.temperatures.first?.celsius ?? 40), theme: theme)
                if !entry.isLive || s.temperatures.isEmpty {
                    NeedsAppNote(text: "Open Task Manager to read the temperature sensors.", theme: theme)
                } else if family == .systemSmall, let main = s.temperatures.first {
                    Spacer(minLength: 0)
                    Text(WFmt.temperature(main.celsius, fahrenheit: s.fahrenheit))
                        .font(.system(size: 38, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(theme.temperature(main.celsius))
                    Text(main.name).font(.system(size: 11)).foregroundStyle(theme.secondary)
                    Meter(fraction: (main.celsius - 20) / 90, color: theme.temperature(main.celsius), track: theme.track)
                    Text(fanText(s)).font(.system(size: 10.5)).foregroundStyle(theme.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                        ForEach(Array(s.temperatures.prefix(6).enumerated()), id: \.offset) { _, temp in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Image(systemName: temp.symbol).font(.system(size: 10))
                                    Text(temp.name).font(.system(size: 10.5)).lineLimit(1)
                                }
                                .foregroundStyle(theme.secondary)
                                Text(WFmt.temperature(temp.celsius, fahrenheit: s.fahrenheit))
                                    .font(.system(size: 20, weight: .semibold)).monospacedDigit()
                                    .foregroundStyle(theme.temperature(temp.celsius))
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Text("\(fanText(s))  ·  Thermal pressure: \(s.thermalState)")
                        .font(.system(size: 10.5)).foregroundStyle(theme.secondary)
                }
            }
        }
    }

    private func fanText(_ s: WidgetSnapshot) -> String {
        guard !s.fans.isEmpty else { return "No fans" }
        let spinning = s.fans.filter { $0 >= 1 }
        return spinning.isEmpty ? "Fans off" : "Fans \(Int(spinning.max() ?? 0)) RPM"
    }
}

// MARK: - Network

struct NetworkWidgetView: View {
    let entry: StatsEntry
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.widgetFamilyOverride) private var familyOverride
    private var family: WidgetFamily { familyOverride ?? systemFamily }

    var body: some View {
        let s = entry.snapshot
        WidgetShell(entry: entry, link: "performance/network") { theme in
            let scale = max((s.networkReceiveHistory + s.networkSendHistory).max() ?? 0, 102_400)
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(symbol: "network", title: "Network", tint: theme.network, theme: theme)
                if family == .systemSmall {
                    // Side by side, the labels don't fit a small widget.
                    VStack(alignment: .leading, spacing: 4) {
                        compactRate("arrow.down", s.networkReceive, theme)
                        compactRate("arrow.up", s.networkSend, theme)
                    }
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        rate("arrow.down", "Download", s.networkReceive, theme)
                        rate("arrow.up", "Upload", s.networkSend, theme)
                    }
                }
                if s.networkReceiveHistory.count > 1 {
                    ZStack {
                        Sparkline(values: s.networkReceiveHistory, maxValue: scale, color: theme.network)
                        Sparkline(values: s.networkSendHistory, maxValue: scale, color: theme.network.opacity(0.6), filled: false)
                    }
                    .frame(maxHeight: family == .systemSmall ? 34 : .infinity)
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func rate(_ symbol: String, _ label: String, _ value: Double, _ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(label, systemImage: symbol).font(.system(size: 10.5)).foregroundStyle(theme.secondary).lineLimit(1)
            Text(WFmt.rate(value)).font(.system(size: 15, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func compactRate(_ symbol: String, _ value: Double, _ theme: WidgetTheme) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.secondary)
            Text(WFmt.rate(value)).font(.system(size: 15, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Storage

struct StorageWidgetView: View {
    let entry: StatsEntry

    var body: some View {
        let s = entry.snapshot
        WidgetShell(entry: entry, link: "performance/disk") { theme in
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(symbol: "internaldrive", title: s.diskName, tint: theme.disk, theme: theme)
                ZStack {
                    Ring(fraction: s.diskUsedFraction, color: theme.disk, track: theme.track, lineWidth: 10)
                    VStack(spacing: 0) {
                        Text(WFmt.storage(s.diskFree)).font(.system(size: 17, weight: .semibold)).monospacedDigit()
                        Text("free").font(.system(size: 9.5)).foregroundStyle(theme.secondary)
                    }
                }
                Text("of \(WFmt.storage(s.diskTotal))").font(.system(size: 10.5)).foregroundStyle(theme.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
