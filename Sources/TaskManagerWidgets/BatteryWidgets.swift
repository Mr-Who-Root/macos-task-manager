import SwiftUI
import TaskManagerShared
import WidgetKit

struct BatteryWidgets: WidgetBundle {
    var body: some Widget {
        BatteryWidget()
        BatteryUsageWidget()
        PowerWidget()
        BatteryHealthWidget()
        SleepWidget()
    }
}

// MARK: - Widget definitions

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BatteryWidget", provider: StatsProvider()) { BatteryWidgetView(entry: $0) }
            .configurationDisplayName("Battery")
            .description("Charge and time left, plus the last 24 hours and the apps using the most power on larger sizes.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct BatteryUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BatteryUsageWidget", provider: StatsProvider()) { BatteryUsageWidgetView(entry: $0) }
            .configurationDisplayName("Battery Usage")
            .description("The apps using the most power right now.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct PowerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PowerWidget", provider: StatsProvider()) { PowerWidgetView(entry: $0) }
            .configurationDisplayName("Power Draw")
            .description("What the whole Mac is drawing, with a live graph, the battery and the power adapter.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BatteryHealthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BatteryHealthWidget", provider: StatsProvider()) { BatteryHealthWidgetView(entry: $0) }
            .configurationDisplayName("Battery Health")
            .description("Maximum capacity, condition and charge cycles.")
            .supportedFamilies([.systemSmall])
    }
}

struct SleepWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SleepWidget", provider: StatsProvider()) { SleepWidgetView(entry: $0) }
            .configurationDisplayName("Preventing Sleep")
            .description("Which apps are keeping your Mac awake, and why.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Text

extension WidgetSnapshot.Battery {
    /// "2 h 15 min left", "Full in 1 h 05 min", "Charging", "Charging on hold" or "Fully charged".
    var timeText: String {
        if isCharging { return timeToFull.map { "Full in \(WFmt.duration($0))" } ?? "Charging" }
        if !pluggedIn { return timeToEmpty.map { "\(WFmt.duration($0)) left" } ?? "Estimating time left…" }
        return status == "Fully charged" ? "Fully charged" : "Charging on hold"
    }

    var shortTimeText: String {
        if isCharging { return timeToFull.map { "Full in \(WFmt.shortDuration($0))" } ?? "Charging" }
        if !pluggedIn { return timeToEmpty.map { "\(WFmt.shortDuration($0)) left" } ?? "Estimating…" }
        return status == "Fully charged" ? "Fully charged" : "Plugged in"
    }

    /// "Charging at 25 W" or "Using 8.1 W" while power flows into or out of the battery.
    var rateText: String? {
        guard let flow = batteryPower, abs(flow) > 0.05 else { return nil }
        return flow > 0 ? "Charging at \(WFmt.watts(flow))" : "Using \(WFmt.watts(flow))"
    }

    /// The rate, or "Not charging" while the adapter is connected but charging is on hold.
    var flowText: String? {
        rateText ?? (pluggedIn && !isCharging && status != "Fully charged" ? "Not charging" : nil)
    }

    var isHealthy: Bool { condition == nil || condition == "Normal" }
}

// MARK: - Building blocks

/// The charge ring, with a bolt while charging.
struct ChargeRing: View {
    let battery: WidgetSnapshot.Battery
    let theme: WidgetTheme
    var lineWidth: CGFloat = 10
    var fontSize: CGFloat = 22

    var body: some View {
        ZStack {
            Ring(fraction: battery.charge, color: theme.charge(battery), track: theme.track, lineWidth: lineWidth)
            VStack(spacing: 0) {
                if battery.isCharging {
                    Image(systemName: "bolt.fill").font(.system(size: fontSize * 0.45, weight: .semibold)).foregroundStyle(theme.good)
                }
                Text(WFmt.percent(battery.charge)).font(.system(size: fontSize, weight: .semibold)).monospacedDigit()
            }
        }
    }
}

/// The battery level over the last 24 hours, one bar per 15 minutes, as on the Battery page.
struct LevelBars: View {
    let levels: [WidgetSnapshot.Level]
    let now: Date
    let theme: WidgetTheme

    private static let slot: TimeInterval = 15 * 60

    var body: some View {
        GeometryReader { geometry in
            let end = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / Self.slot).rounded(.down) * Self.slot + Self.slot)
            let start = end.addingTimeInterval(-24 * 3600)
            let width = geometry.size.width / 96
            let gap = max(0.5, width * 0.2)
            let h = geometry.size.height
            let bars = levels.compactMap { level -> (rect: CGRect, pluggedIn: Bool)? in
                let index = Int((level.time.timeIntervalSince(start) / Self.slot).rounded(.down))
                guard (0..<96).contains(index) else { return nil }
                let height = max(1.5, h * min(max(level.charge, 0), 1))
                return (CGRect(x: CGFloat(index) * width + gap / 2, y: h - height, width: width - gap, height: height), level.pluggedIn)
            }
            let radius = min(1.5, (width - gap) / 2)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(theme.track).frame(height: 1).offset(y: h - 1)
                Path { p in
                    for bar in bars where !bar.pluggedIn { p.addRoundedRect(in: bar.rect, cornerSize: CGSize(width: radius, height: radius)) }
                }
                .fill(theme.onBattery)
                Path { p in
                    for bar in bars where bar.pluggedIn { p.addRoundedRect(in: bar.rect, cornerSize: CGSize(width: radius, height: radius)) }
                }
                .fill(theme.good)
            }
        }
    }
}

/// A small icon and value: "⚡ 6.7 W".
struct StatChip: View {
    let symbol: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(tint)
            Text(value).font(.system(size: 11, weight: .semibold)).monospacedDigit().lineLimit(1)
        }
    }
}

struct LegendDot: View {
    let color: Color
    let title: String
    let theme: WidgetTheme

    var body: some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 7, height: 7)
            Text(title).font(.system(size: 9.5)).foregroundStyle(theme.secondary)
        }
    }
}

/// Apps by power, with Task Manager's heat map.
struct PowerAppRows: View {
    let apps: [WidgetSnapshot.PowerApp]
    let theme: WidgetTheme
    var compact = false
    var spacing: CGFloat?

    var body: some View {
        VStack(spacing: spacing ?? (compact ? 3 : 4)) {
            ForEach(Array(apps.enumerated()), id: \.offset) { _, app in
                HStack(spacing: 6) {
                    AppIcon(data: app.icon, theme: theme)
                    Text(app.name).font(.system(size: 11.5)).lineLimit(1)
                    if app.keepsAwake {
                        Image(systemName: "moon.zzz.fill").font(.system(size: 9)).foregroundStyle(theme.secondary)
                    }
                    Spacer(minLength: 4)
                    if app.watts != nil && !compact {
                        Text(app.usage).font(.system(size: 10.5)).foregroundStyle(theme.secondary).lineLimit(1)
                    }
                    Text(app.watts.map(WFmt.watts) ?? app.usage)
                        .font(.system(size: 11)).monospacedDigit().lineLimit(1)
                        .frame(width: 62, height: compact ? 18 : 20, alignment: .trailing)
                        .padding(.trailing, 4)
                        .background(theme.heat(app.heat))
                }
            }
        }
    }
}

struct BlockerRow: View {
    let blocker: WidgetSnapshot.SleepBlocker
    let theme: WidgetTheme

    var body: some View {
        HStack(spacing: 7) {
            AppIcon(data: blocker.icon, theme: theme, size: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(blocker.name).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                if !blocker.reason.isEmpty {
                    Text(blocker.reason).font(.system(size: 10)).foregroundStyle(theme.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Label(blocker.keepsDisplayOn ? "Display on" : "No sleep", systemImage: blocker.keepsDisplayOn ? "display" : "moon.zzz")
                .font(.system(size: 10)).foregroundStyle(theme.secondary).lineLimit(1).fixedSize()
        }
    }
}

/// For desktop Macs.
struct NoBatteryNote: View {
    let theme: WidgetTheme

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "powerplug").font(.system(size: 18)).foregroundStyle(theme.secondary)
            Text("This Mac has no battery.").font(.system(size: 11)).multilineTextAlignment(.center).foregroundStyle(theme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Rounds a power scale up to a tidy figure.
private func powerScale(_ values: [Double]) -> Double {
    let peak = max(values.max() ?? 0, 10)
    return [10.0, 20, 30, 50, 75, 100, 150, 200].first { $0 >= peak } ?? peak
}

// MARK: - Battery

struct BatteryWidgetView: View {
    let entry: StatsEntry
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.widgetFamilyOverride) private var familyOverride
    private var family: WidgetFamily { familyOverride ?? systemFamily }

    var body: some View {
        let s = entry.snapshot
        WidgetShell(entry: entry, link: "battery") { theme in
            if let battery = s.battery {
                switch family {
                case .systemSmall: small(battery, theme)
                case .systemLarge: large(s, battery, theme)
                default: medium(battery, theme)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeader(symbol: "battery.0percent", title: "Battery", tint: theme.secondary, theme: theme)
                    NoBatteryNote(theme: theme)
                }
            }
        }
    }

    private func small(_ battery: WidgetSnapshot.Battery, _ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(symbol: battery.symbol, title: "Battery", tint: theme.charge(battery), theme: theme)
            ChargeRing(battery: battery, theme: theme)
            Text(battery.shortTimeText).font(.system(size: 10.5)).foregroundStyle(theme.secondary).lineLimit(1)
                .frame(maxWidth: .infinity)
        }
    }

    private func medium(_ battery: WidgetSnapshot.Battery, _ theme: WidgetTheme) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(symbol: battery.symbol, title: "Battery", tint: theme.charge(battery), theme: theme)
                ChargeRing(battery: battery, theme: theme)
            }
            .frame(width: 112)
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(battery.status).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text([battery.timeText, battery.rateText].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(theme.secondary).lineLimit(1)
                }
                if battery.levels.isEmpty {
                    Spacer(minLength: 0)
                    Text("The last 24 hours fill in while Task Manager runs.")
                        .font(.system(size: 10)).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                } else {
                    LevelBars(levels: battery.levels, now: entry.date, theme: theme).frame(maxHeight: .infinity)
                    Text("Last 24 hours").font(.system(size: 9.5)).foregroundStyle(theme.secondary)
                }
                stats(battery, theme)
            }
        }
    }

    private func large(_ s: WidgetSnapshot, _ battery: WidgetSnapshot.Battery, _ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ChargeRing(battery: battery, theme: theme, lineWidth: 11, fontSize: 24).frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 3) {
                    WidgetHeader(symbol: battery.symbol, title: "Battery", tint: theme.charge(battery), theme: theme)
                    Text(battery.status).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text([battery.timeText, battery.rateText].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(theme.secondary).lineLimit(1)
                    stats(battery, theme).padding(.top, 3)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Last 24 hours").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(theme.secondary)
                    Spacer()
                    LegendDot(color: theme.onBattery, title: "On battery", theme: theme)
                    LegendDot(color: theme.good, title: "Plugged in", theme: theme)
                }
                if battery.levels.isEmpty {
                    Text("Recorded while Task Manager is running.").font(.system(size: 10.5)).foregroundStyle(theme.secondary)
                        .frame(maxWidth: .infinity, minHeight: 46)
                } else {
                    LevelBars(levels: battery.levels, now: entry.date, theme: theme).frame(height: 46)
                    HStack {
                        Text("24 h ago")
                        Spacer()
                        Text("Now")
                    }
                    .font(.system(size: 9)).foregroundStyle(theme.secondary)
                }
            }
            Divider().overlay(theme.track)
            if entry.isLive, let apps = s.powerApps, !apps.isEmpty {
                Text("Using the most power").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(theme.secondary)
                PowerAppRows(apps: Array(apps.prefix(4)), theme: theme, compact: true)
                Spacer(minLength: 0)
                if let blockers = s.sleepBlockers {
                    HStack(spacing: 5) {
                        Image(systemName: "moon.zzz").font(.system(size: 10))
                        Text(blockers.isEmpty ? "Nothing is keeping your Mac awake" : "Keeping it awake: \(blockers.map(\.name).joined(separator: ", "))")
                            .font(.system(size: 10.5)).lineLimit(1)
                    }
                    .foregroundStyle(theme.secondary)
                }
            } else {
                NeedsAppNote(text: "Open Task Manager to see which apps use the most power.", theme: theme)
            }
        }
    }

    private func stats(_ battery: WidgetSnapshot.Battery, _ theme: WidgetTheme) -> some View {
        HStack(spacing: 10) {
            if let draw = battery.powerDraw {
                StatChip(symbol: "bolt.fill", value: WFmt.watts(draw), tint: theme.power)
            }
            if let health = battery.health {
                StatChip(symbol: "heart.fill", value: WFmt.percent(health), tint: battery.isHealthy ? theme.good : theme.critical)
            }
            if let celsius = battery.temperature {
                StatChip(symbol: "thermometer.medium", value: WFmt.temperature(celsius, fahrenheit: entry.snapshot.fahrenheit), tint: theme.temperature(celsius))
            }
        }
    }
}

// MARK: - Battery usage

struct BatteryUsageWidgetView: View {
    let entry: StatsEntry
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.widgetFamilyOverride) private var familyOverride
    private var family: WidgetFamily { familyOverride ?? systemFamily }

    var body: some View {
        let s = entry.snapshot
        WidgetShell(entry: entry, link: "battery") { theme in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    WidgetHeader(symbol: "bolt.batteryblock", title: "Battery usage", tint: theme.power, theme: theme)
                    if let draw = s.battery?.powerDraw {
                        Text("Whole Mac \(WFmt.watts(draw))").font(.system(size: 10.5)).foregroundStyle(theme.secondary).fixedSize()
                    }
                }
                if entry.isLive, let apps = s.powerApps, !apps.isEmpty {
                    PowerAppRows(apps: Array(apps.prefix(family == .systemLarge ? 9 : 4)), theme: theme, spacing: family == .systemLarge ? 9 : nil)
                    Spacer(minLength: 0)
                    if family == .systemLarge {
                        HStack(spacing: 4) {
                            Image(systemName: "moon.zzz.fill").font(.system(size: 9))
                            Text("Keeping your Mac awake").font(.system(size: 10))
                        }
                        .foregroundStyle(theme.secondary)
                    }
                } else {
                    NeedsAppNote(text: "Open Task Manager to see which apps use the most power.", theme: theme)
                }
            }
        }
    }
}

// MARK: - Power draw

struct PowerWidgetView: View {
    let entry: StatsEntry
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.widgetFamilyOverride) private var familyOverride
    private var family: WidgetFamily { familyOverride ?? systemFamily }

    var body: some View {
        let s = entry.snapshot
        WidgetShell(entry: entry, link: "battery") { theme in
            if family == .systemMedium {
                HStack(spacing: 16) {
                    main(s, theme).frame(width: 140)
                    details(s, theme)
                }
            } else {
                main(s, theme)
            }
        }
    }

    private func main(_ s: WidgetSnapshot, _ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(symbol: "bolt.fill", title: "Power draw", tint: theme.power, theme: theme)
            if let battery = s.battery, let draw = battery.powerDraw {
                Text(WFmt.watts(draw)).font(.system(size: 30, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(battery.pluggedIn ? "From power adapter" : "From battery").font(.system(size: 10.5)).foregroundStyle(theme.secondary)
                if battery.powerHistory.count > 1 {
                    Sparkline(values: battery.powerHistory, maxValue: powerScale(battery.powerHistory), color: theme.power)
                        .frame(maxHeight: .infinity)
                } else {
                    Spacer(minLength: 0)
                }
            } else if s.battery == nil && entry.isLive {
                NeedsAppNote(text: "This Mac doesn't report its power draw.", theme: theme, symbol: "powerplug")
            } else {
                NeedsAppNote(text: "Open Task Manager to measure power draw.", theme: theme)
            }
        }
    }

    private func details(_ s: WidgetSnapshot, _ theme: WidgetTheme) -> some View {
        let battery = s.battery
        return VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)
            if let battery {
                row("Battery", "\(WFmt.percent(battery.charge)) · \(battery.flowText ?? battery.shortTimeText)", theme)
                row("Adapter", battery.adapterWatts.map { "\(Int($0.rounded())) W" } ?? (battery.pluggedIn ? "Connected" : "Not connected"), theme)
                row("Low Power Mode", battery.lowPowerMode ? "On" : "Off", theme)
            }
            if entry.isLive, let top = s.powerApps?.first {
                row("Top app", "\(top.name) \(top.watts.map(WFmt.watts) ?? top.usage)", theme)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: String, _ value: String, _ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 10)).foregroundStyle(theme.secondary)
            Text(value).font(.system(size: 12, weight: .medium)).monospacedDigit().lineLimit(1)
        }
    }
}

// MARK: - Battery health

struct BatteryHealthWidgetView: View {
    let entry: StatsEntry

    var body: some View {
        let s = entry.snapshot
        WidgetShell(entry: entry, link: "battery") { theme in
            let color = s.battery.map { $0.isHealthy ? theme.good : theme.critical } ?? theme.good
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(symbol: "heart.fill", title: "Battery health", tint: color, theme: theme)
                if let battery = s.battery, let health = battery.health {
                    ZStack {
                        Ring(fraction: health, color: color, track: theme.track, lineWidth: 10)
                        VStack(spacing: 0) {
                            Text(WFmt.percent(health)).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                            Text("capacity").font(.system(size: 9.5)).foregroundStyle(theme.secondary)
                        }
                    }
                    Text([battery.condition, battery.cycleCount.map { "\($0) cycles" }].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 10.5)).foregroundStyle(theme.secondary).lineLimit(1)
                        .frame(maxWidth: .infinity)
                } else if s.battery == nil && entry.isLive {
                    NoBatteryNote(theme: theme)
                } else {
                    NeedsAppNote(text: "Open Task Manager to read the battery's health.", theme: theme)
                }
            }
        }
    }
}

// MARK: - Preventing sleep

struct SleepWidgetView: View {
    let entry: StatsEntry
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.widgetFamilyOverride) private var familyOverride
    private var family: WidgetFamily { familyOverride ?? systemFamily }

    var body: some View {
        let s = entry.snapshot
        WidgetShell(entry: entry, link: "battery") { theme in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    WidgetHeader(symbol: "moon.zzz.fill", title: "Preventing sleep", tint: theme.accent(s.accent), theme: theme)
                    if family == .systemMedium, let blockers = s.sleepBlockers, !blockers.isEmpty {
                        Text(blockers.count == 1 ? "1 app" : "\(blockers.count) apps").font(.system(size: 10.5)).foregroundStyle(theme.secondary).fixedSize()
                    }
                }
                if !entry.isLive || s.sleepBlockers == nil {
                    NeedsAppNote(text: "Open Task Manager to see what keeps your Mac awake.", theme: theme)
                } else if let blockers = s.sleepBlockers, !blockers.isEmpty {
                    if family == .systemMedium {
                        ForEach(Array(blockers.prefix(3).enumerated()), id: \.offset) { _, blocker in
                            BlockerRow(blocker: blocker, theme: theme)
                        }
                        Spacer(minLength: 0)
                        if blockers.count > 3 {
                            Text("and \(blockers.count - 3) more").font(.system(size: 10)).foregroundStyle(theme.secondary)
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\(blockers.count)").font(.system(size: 30, weight: .semibold)).monospacedDigit()
                            Text(blockers.count == 1 ? "app keeps it awake" : "apps keep it awake")
                                .font(.system(size: 10.5)).foregroundStyle(theme.secondary).lineLimit(2)
                        }
                        ForEach(Array(blockers.prefix(2).enumerated()), id: \.offset) { _, blocker in
                            HStack(spacing: 5) {
                                AppIcon(data: blocker.icon, theme: theme, size: 14)
                                Text(blocker.name).font(.system(size: 11)).lineLimit(1)
                                Spacer(minLength: 2)
                                Image(systemName: blocker.keepsDisplayOn ? "display" : "moon.zzz").font(.system(size: 9)).foregroundStyle(theme.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    Spacer(minLength: 0)
                    HStack(spacing: 10) {
                        Image(systemName: "moon.stars.fill").font(.system(size: family == .systemMedium ? 30 : 24))
                            .foregroundStyle(theme.accent(s.accent))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Can sleep").font(.system(size: 15, weight: .semibold))
                            Text("Nothing is keeping your Mac awake.").font(.system(size: 10.5)).foregroundStyle(theme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
