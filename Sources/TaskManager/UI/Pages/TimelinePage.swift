import Charts
import SwiftUI

/// Rewind: what the Mac was doing, minute by minute. Hover over the graph to see any moment,
/// click to keep it, and see which apps were behind it.
struct TimelinePage: View {
    @Environment(Monitor.self) private var monitor
    @Environment(AppState.self) private var state
    @State private var metric = TimelineStore.Metric.cpu
    @AppStorage("timelineRange") private var range = Window.sixHours
    @State private var hover: Date?
    @State private var pinned: Date?

    enum Window: Int, CaseIterable, Identifiable {
        case hour = 3600, sixHours = 21_600, day = 86_400
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .hour: return "1 hour"
            case .sixHours: return "6 hours"
            case .day: return "24 hours"
            }
        }
    }

    var body: some View {
        let end = Date()
        let start = end.addingTimeInterval(-TimeInterval(range.rawValue))
        let minutes = monitor.timeline.minutes.filter { $0.time >= start }
        let selected = minute(at: pinned ?? hover, in: minutes) ?? minutes.last
        VStack(spacing: 0) {
            PageHeader(title: "Timeline") {
                CommandButton(title: "Why is my Mac slow?", systemImage: "stethoscope") { state.showDiagnosis = true }
                CommandSeparator()
                Picker("Range", selection: $range) {
                    ForEach(Window.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if minutes.isEmpty {
                ContentUnavailableView(
                    "Recording…",
                    systemImage: "chart.xyaxis.line",
                    description: Text("The timeline records what your Mac is doing once a minute while Task Manager runs. The first minute appears shortly.")
                )
                .foregroundStyle(Fluent.textSecondary)
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Picker("Measure", selection: $metric) {
                                ForEach(TimelineStore.Metric.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                            Spacer()
                            if pinned != nil {
                                Button("Follow the latest") { pinned = nil }
                                    .buttonStyle(.link)
                                    .font(.system(size: 12))
                            }
                        }
                        moments(minutes)
                        TimelineCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(selected.map { readout($0) } ?? "")
                                    .font(.system(size: 12))
                                    .monospacedDigit()
                                    .foregroundStyle(Fluent.textSecondary)
                                chart(minutes, start: start, end: end, selected: selected?.time)
                                    .frame(height: 220)
                            }
                            .padding(14)
                        }
                        if let selected {
                            MomentDetail(minute: selected, metric: metric, energyAvailable: monitor.energyAvailable)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    // MARK: Chart

    private func chart(_ minutes: [TimelineStore.Minute], start: Date, end: Date, selected: Date?) -> some View {
        let values = Self.segmented(minutes.compactMap { m in metric.value(m).map { (m.time, $0) } })
        let top = scale(values.map(\.value))
        let color = Self.color(metric)
        // A run of one minute draws no line or area, so it gets a dot.
        let runLengths = Dictionary(grouping: values, by: \.segment).mapValues(\.count)
        return Chart {
            ForEach(values, id: \.time) { point in
                AreaMark(x: .value("Time", point.time), y: .value(metric.title, point.value), series: .value("Run", point.segment))
                    .foregroundStyle(color.opacity(0.18))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", point.time), y: .value(metric.title, point.value), series: .value("Run", point.segment))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.6))
                    .interpolationMethod(.monotone)
            }
            ForEach(values.filter { runLengths[$0.segment] == 1 }, id: \.time) { point in
                PointMark(x: .value("Time", point.time), y: .value(metric.title, point.value))
                    .symbolSize(28)
                    .foregroundStyle(color)
            }
            ForEach(minutes.filter { !$0.events.isEmpty }) { minute in
                PointMark(x: .value("Time", minute.time), y: .value("Event", top * 0.97))
                    .symbol(.diamond)
                    .symbolSize(40)
                    .foregroundStyle(ChargeScale.low)
            }
            if let selected {
                RuleMark(x: .value("Selected", selected))
                    .foregroundStyle(Fluent.textSecondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: pinned == nil ? [3, 3] : []))
            }
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...top)
        .chartXAxis {
            AxisMarks(values: Self.ticks(from: start, to: end, range: range)) { _ in
                AxisGridLine().foregroundStyle(Fluent.divider)
                AxisValueLabel(format: .dateTime.hour().minute()).foregroundStyle(Fluent.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, top / 2, top]) { value in
                AxisGridLine().foregroundStyle(Fluent.divider)
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(format(v, short: true)).foregroundStyle(Fluent.textSecondary) }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        guard case .active(let location) = phase, let plot = proxy.plotFrame else {
                            hover = nil
                            return
                        }
                        hover = proxy.value(atX: location.x - geometry[plot].origin.x, as: Date.self)
                    }
                    .gesture(SpatialTapGesture().onEnded { tap in
                        guard let plot = proxy.plotFrame,
                              let date = proxy.value(atX: tap.location.x - geometry[plot].origin.x, as: Date.self) else { return }
                        pinned = minute(at: date, in: minutes)?.time
                    })
            }
        }
    }

    /// Splits the points into runs wherever minutes are missing (Task Manager wasn't running), so the
    /// graph doesn't draw a line across the gap.
    static func segmented(_ points: [(Date, Double)]) -> [(time: Date, value: Double, segment: Int)] {
        var segment = 0
        var previous: Date?
        return points.map { time, value in
            if let previous, time.timeIntervalSince(previous) > 150 { segment += 1 }
            previous = time
            return (time, value, segment)
        }
    }

    /// Clock-aligned ticks (every 15 minutes, hour or 3 hours) that keep clear of the edges, where
    /// labels would be clipped.
    static func ticks(from start: Date, to end: Date, range: Window, calendar: Calendar = .current) -> [Date] {
        let step: Int = range == .hour ? 15 : (range == .sixHours ? 60 : 180)
        let margin = end.timeIntervalSince(start) * 0.06
        var tick = calendar.startOfDay(for: start)
        var ticks: [Date] = []
        while tick < end {
            if tick.timeIntervalSince(start) >= margin && end.timeIntervalSince(tick) >= margin { ticks.append(tick) }
            guard let next = calendar.date(byAdding: .minute, value: step, to: tick) else { break }
            tick = next
        }
        return ticks
    }

    /// The three highest minutes, at least ten minutes apart.
    static func biggestMoments(_ minutes: [TimelineStore.Minute], metric: TimelineStore.Metric) -> [TimelineStore.Minute] {
        var picked: [TimelineStore.Minute] = []
        for minute in minutes.sorted(by: { (metric.value($0) ?? 0) > (metric.value($1) ?? 0) })
        where picked.count < 3 && picked.allSatisfy({ abs($0.time.timeIntervalSince(minute.time)) >= 600 }) {
            picked.append(minute)
        }
        return picked
    }

    @ViewBuilder
    private func moments(_ minutes: [TimelineStore.Minute]) -> some View {
        let picked = Self.biggestMoments(minutes, metric: metric)
        if !picked.isEmpty {
            HStack(spacing: 8) {
                Text("Biggest moments").font(.system(size: 12, weight: .semibold)).foregroundStyle(Fluent.textSecondary)
                ForEach(picked) { minute in
                    Button {
                        pinned = minute.time
                    } label: {
                        Text("\(minute.time.formatted(date: .omitted, time: .shortened)) · \(metric.value(minute).map { format($0, short: false) } ?? "—")")
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Capsule().fill(pinned == minute.time ? Fluent.accent.opacity(0.18) : Fluent.subtleHover))
                            .overlay(Capsule().strokeBorder(pinned == minute.time ? Fluent.accent.opacity(0.5) : Fluent.cardStroke))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Fluent.textPrimary)
                }
                Spacer()
            }
        }
    }

    private func minute(at date: Date?, in minutes: [TimelineStore.Minute]) -> TimelineStore.Minute? {
        guard let date else { return nil }
        return minutes.min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }
            .flatMap { abs($0.time.timeIntervalSince(date)) <= 120 ? $0 : nil }
    }

    private func readout(_ minute: TimelineStore.Minute) -> String {
        let time = minute.time.formatted(date: .omitted, time: .shortened)
        let value = metric.value(minute).map { format($0, short: false) } ?? "not recorded"
        let lead = pinned == nil && hover == nil ? "Latest minute, \(time)" : time
        return "\(lead) · \(metric.title) \(value)" + (minute.events.isEmpty ? "" : " · " + minute.events.joined(separator: " · "))
    }

    private func scale(_ values: [Double]) -> Double {
        switch metric {
        case .cpu, .memory: return 1
        case .power: return Fmt.niceCeiling(values.max() ?? 0, minimum: 10)
        case .disk, .network: return Fmt.niceCeiling(values.max() ?? 0, minimum: 1_048_576)
        }
    }

    private func format(_ value: Double, short: Bool) -> String {
        switch metric {
        case .cpu, .memory: return Fmt.wholePercent(value)
        case .disk, .network: return short ? Fmt.bytes(value) + "/s" : Fmt.byteRate(value)
        case .power: return Fmt.watts(value)
        }
    }

    static func color(_ metric: TimelineStore.Metric) -> Color {
        switch metric {
        case .cpu: return ResourceColor.cpu
        case .memory: return ResourceColor.memory
        case .disk: return ResourceColor.disk
        case .network: return ResourceColor.network
        case .power: return ChargeScale.low
        }
    }
}

// MARK: - The selected moment

private struct MomentDetail: View {
    let minute: TimelineStore.Minute
    let metric: TimelineStore.Metric
    let energyAvailable: Bool
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let apps = minute.apps.sorted { metric.value($0) > metric.value($1) }.prefix(8)
        HStack(alignment: .top, spacing: 14) {
            TimelineCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(minute.time.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 15, weight: .semibold))
                    KeyValueGrid(rows: systemRows)
                    if !minute.events.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(minute.events, id: \.self) { event in
                                Label(event, systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(ChargeScale.low)
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 240)
            TimelineCard {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("Apps at this moment").frame(maxWidth: .infinity, alignment: .leading)
                        column("CPU", .cpu, width: 60)
                        column("Memory", .memory, width: 80)
                        if energyAvailable { column("Power", .power, width: 70) }
                        column("Disk", .disk, width: 80)
                        column("Network", .network, width: 80)
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(Fluent.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    Rectangle().fill(Fluent.divider).frame(height: 1)
                    if apps.isEmpty {
                        Text("Nothing stood out.").font(.system(size: 12)).foregroundStyle(Fluent.textSecondary).frame(height: 40)
                    }
                    ForEach(Array(apps)) { app in
                        HStack(spacing: 0) {
                            HStack(spacing: 6) {
                                ProcessIcon(path: app.iconPath).frame(width: 16, height: 16)
                                Text(app.name).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            cell(Fmt.percent(app.cpu), .cpu, width: 60)
                            cell(Fmt.bytes(app.memory), .memory, width: 80)
                            if energyAvailable { cell(app.power.map(Fmt.watts) ?? "", .power, width: 70) }
                            cell(Fmt.byteRate(app.disk), .disk, width: 80)
                            cell(Fmt.byteRate(app.network), .network, width: 80)
                        }
                        .font(.system(size: 12.5))
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private var systemRows: [(String, String)] {
        var rows = [
            ("CPU", Fmt.wholePercent(minute.cpu)),
            ("Memory", Fmt.wholePercent(minute.memory)),
            ("Disk", Fmt.byteRate(minute.disk)),
            ("Network", Fmt.byteRate(minute.network)),
        ]
        if let power = minute.power { rows.append(("Power draw", Fmt.watts(power))) }
        if let celsius = minute.temperature { rows.append(("CPU temperature", Fmt.temperature(celsius, fahrenheit: settings.useFahrenheit))) }
        return rows
    }

    private func column(_ title: String, _ m: TimelineStore.Metric, width: CGFloat) -> some View {
        Text(title)
            .fontWeight(m == metric ? .semibold : .regular)
            .foregroundStyle(m == metric ? Fluent.textPrimary : Fluent.textSecondary)
            .frame(width: width, alignment: .trailing)
    }

    private func cell(_ text: String, _ m: TimelineStore.Metric, width: CGFloat) -> some View {
        Text(text)
            .monospacedDigit()
            .fontWeight(m == metric ? .semibold : .regular)
            .foregroundStyle(m == metric ? Fluent.textPrimary : Fluent.textSecondary)
            .frame(width: width, alignment: .trailing)
    }
}

private struct TimelineCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).fill(Fluent.card))
            .overlay(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).strokeBorder(Fluent.cardStroke))
    }
}
