import SwiftUI
import TaskManagerShared
import WidgetKit

@main
struct TaskManagerWidgetBundle: WidgetBundle {
    // A bundle's body takes at most ten widgets, so they come in groups.
    var body: some Widget {
        ResourceWidgets().body
        BatteryWidgets().body
        OverviewWidgets().body
    }
}

struct ResourceWidgets: WidgetBundle {
    var body: some Widget {
        CPUWidget()
        MemoryWidget()
        GPUWidget()
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
            .description("Processor usage with a live graph and every core, plus the busiest apps on the large size.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct MemoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MemoryWidget", provider: StatsProvider()) { MemoryWidgetView(entry: $0) }
            .configurationDisplayName("Memory")
            .description("Memory in use, compressed, cached and swap, plus the apps using the most on the large size.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct NetworkWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NetworkWidget", provider: StatsProvider()) { NetworkWidgetView(entry: $0) }
            .configurationDisplayName("Network")
            .description("Upload and download speed.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct StorageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StorageWidget", provider: StatsProvider()) { StorageWidgetView(entry: $0) }
            .configurationDisplayName("Storage")
            .description("Free space on your startup disk, plus disk activity on the medium size.")
            .supportedFamilies([.systemSmall, .systemMedium])
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

    /// "0 W", "86 mW", "1.4 W", "18 W".
    static func watts(_ value: Double) -> String {
        let v = abs(value)
        if v < 0.0005 { return "0 W" }
        if v < 0.9995 { return "\(Int((v * 1000).rounded())) mW" }
        return v < 10 ? String(format: "%.1f W", v) : String(format: "%.0f W", v)
    }

    /// "45 min", "2 h 05 min".
    static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : String(format: "%d h %02d min", minutes / 60, minutes % 60)
    }

    /// "45m", "2h 05m", for tight spaces.
    static func shortDuration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : String(format: "%dh %02dm", minutes / 60, minutes % 60)
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

/// An app's icon from the snapshot, or a blank tile.
struct AppIcon: View {
    let data: Data?
    let theme: WidgetTheme
    var size: CGFloat = 16

    var body: some View {
        if let data, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size / 4).fill(theme.track).frame(width: size, height: size)
        }
    }
}

/// Shown on widgets that need Task Manager running (processes, sensors).
struct NeedsAppNote: View {
    let text: String
    let theme: WidgetTheme
    var symbol = "macwindow.badge.plus"

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(theme.secondary)
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
            } else if family == .systemLarge {
                large(s, theme)
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

    private func large(_ s: WidgetSnapshot, _ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ZStack {
                    Ring(fraction: s.cpu, color: theme.cpu, track: theme.track, lineWidth: 10)
                    Text(WFmt.percent(s.cpu)).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                }
                .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 4) {
                    WidgetHeader(symbol: "cpu", title: "CPU", tint: theme.cpu, theme: theme)
                    Text(s.cpuName).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    if s.processCount > 0 {
                        Text("\(s.processCount) processes · \(s.threadCount.formatted()) threads")
                            .font(.system(size: 10.5)).foregroundStyle(theme.secondary).lineLimit(1)
                    }
                    Text("Up \(WFmt.uptime(s.uptime))").font(.system(size: 10.5)).foregroundStyle(theme.secondary)
                }
            }
            if s.cpuHistory.count > 1 {
                Sparkline(values: s.cpuHistory, maxValue: 1, color: theme.cpu).frame(minHeight: 50, maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
            if !s.perCore.isEmpty {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(s.perCore.prefix(32).enumerated()), id: \.offset) { _, core in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 1.5).fill(theme.track)
                            RoundedRectangle(cornerRadius: 1.5).fill(theme.cpu).frame(height: max(2, 26 * core))
                        }
                        .frame(height: 26)
                    }
                }
            }
            Divider().overlay(theme.track)
            if entry.isLive && !s.topApps.isEmpty {
                AppRows(apps: Array(s.topApps.prefix(4)), theme: theme, compact: true)
            } else {
                NeedsAppNote(text: "Open Task Manager to see which apps are busiest.", theme: theme)
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
            } else if family == .systemLarge {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            WidgetHeader(symbol: "memorychip", title: "Memory", tint: theme.memory, theme: theme)
                            ring
                        }
                        .frame(width: 112)
                        VStack(alignment: .leading, spacing: 5) {
                            row("In use", "\(WFmt.gigabytes(s.memoryUsed)) of \(WFmt.gigabytes(s.memoryTotal))", theme)
                            row("Compressed", WFmt.gigabytes(s.memoryCompressed), theme)
                            row("Cached", WFmt.gigabytes(s.memoryCached), theme)
                            if entry.isLive {
                                row("Swap", WFmt.gigabytes(s.swapUsed), theme)
                                row("Pressure", s.memoryPressure, theme)
                            }
                        }
                    }
                    .frame(height: 128)
                    composition(s, theme)
                    if s.memoryHistory.count > 1 {
                        Sparkline(values: s.memoryHistory, maxValue: 1, color: theme.memory).frame(minHeight: 32, maxHeight: .infinity)
                    } else {
                        Spacer(minLength: 0)
                    }
                    Divider().overlay(theme.track)
                    if entry.isLive, let apps = s.memoryApps, !apps.isEmpty {
                        AppRows(apps: Array(apps.prefix(4)), theme: theme, compact: true)
                    } else {
                        NeedsAppNote(text: "Open Task Manager to see which apps use the most memory.", theme: theme)
                    }
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

    /// In use (apps and wired), compressed and cached, like the Performance page's composition bar.
    private func composition(_ s: WidgetSnapshot, _ theme: WidgetTheme) -> some View {
        let total = Double(max(s.memoryTotal, 1))
        let compressed = Double(s.memoryCompressed) / total
        let used = max(Double(s.memoryUsed) / total - compressed, 0)
        let cached = min(Double(s.memoryCached) / total, max(1 - used - compressed, 0))
        return GeometryReader { geometry in
            HStack(spacing: 1.5) {
                Rectangle().fill(theme.memory).frame(width: geometry.size.width * used)
                Rectangle().fill(theme.memory.opacity(0.6)).frame(width: geometry.size.width * compressed)
                Rectangle().fill(theme.memory.opacity(0.25)).frame(width: geometry.size.width * cached)
                Spacer(minLength: 0)
            }
            .background(theme.track)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 12)
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
                    AppIcon(data: app.icon, theme: theme)
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
                    let large = family == .systemLarge
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: large ? 16 : 10) {
                        ForEach(Array(s.temperatures.prefix(large ? 12 : 6).enumerated()), id: \.offset) { _, temp in
                            VStack(alignment: .leading, spacing: large ? 4 : 2) {
                                HStack(spacing: 4) {
                                    Image(systemName: temp.symbol).font(.system(size: 10))
                                    Text(temp.name).font(.system(size: 10.5)).lineLimit(1)
                                }
                                .foregroundStyle(theme.secondary)
                                Text(WFmt.temperature(temp.celsius, fahrenheit: s.fahrenheit))
                                    .font(.system(size: large ? 24 : 20, weight: .semibold)).monospacedDigit()
                                    .foregroundStyle(theme.temperature(temp.celsius))
                                if large {
                                    Meter(fraction: (temp.celsius - 20) / 90, color: theme.temperature(temp.celsius), track: theme.track)
                                        .padding(.trailing, 10)
                                }
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
                    if family == .systemLarge {
                        Text("Peak in the last minute: ↓ \(WFmt.rate(s.networkReceiveHistory.max() ?? 0))  ·  ↑ \(WFmt.rate(s.networkSendHistory.max() ?? 0))")
                            .font(.system(size: 10.5)).foregroundStyle(theme.secondary).lineLimit(1)
                    }
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
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.widgetFamilyOverride) private var familyOverride
    private var family: WidgetFamily { familyOverride ?? systemFamily }

    var body: some View {
        let s = entry.snapshot
        WidgetShell(entry: entry, link: "performance/disk") { theme in
            let ring = ZStack {
                Ring(fraction: s.diskUsedFraction, color: theme.disk, track: theme.track, lineWidth: 10)
                VStack(spacing: 0) {
                    Text(WFmt.storage(s.diskFree)).font(.system(size: 17, weight: .semibold)).monospacedDigit()
                    Text("free").font(.system(size: 9.5)).foregroundStyle(theme.secondary)
                }
            }
            if family == .systemMedium {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        WidgetHeader(symbol: "internaldrive", title: s.diskName, tint: theme.disk, theme: theme)
                        ring
                    }
                    .frame(width: 112)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(WFmt.storage(s.diskTotal - min(s.diskFree, s.diskTotal))) used of \(WFmt.storage(s.diskTotal))")
                            .font(.system(size: 11, weight: .medium)).lineLimit(1)
                        HStack(alignment: .top, spacing: 14) {
                            rate("arrow.down.doc", "Read", s.diskRead, theme)
                            rate("arrow.up.doc", "Write", s.diskWrite, theme)
                        }
                        if let read = s.diskReadHistory, let write = s.diskWriteHistory, read.count > 1 {
                            let scale = max((read + write).max() ?? 0, 1_048_576)
                            ZStack {
                                Sparkline(values: read, maxValue: scale, color: theme.disk)
                                Sparkline(values: write, maxValue: scale, color: theme.disk.opacity(0.6), filled: false)
                            }
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeader(symbol: "internaldrive", title: s.diskName, tint: theme.disk, theme: theme)
                    ring
                    Text("of \(WFmt.storage(s.diskTotal))").font(.system(size: 10.5)).foregroundStyle(theme.secondary)
                        .frame(maxWidth: .infinity)
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
}
