import SwiftUI

/// Component temperatures and fan speeds from the SMC and the HID sensor hub.
struct TemperaturesPage: View {
    @Environment(Monitor.self) private var monitor
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var state
    @State private var expanded: Set<SensorComponent> = []

    var body: some View {
        let sensors = monitor.system.sensors
        let components = sensors.components
        VStack(spacing: 0) {
            PageHeader(title: "Temperatures") {
                ThermalStateBadge(state: sensors.thermalState, text: sensors.thermalStateText)
                    .padding(.trailing, 8)
                CommandBarMenu(title: settings.useFahrenheit ? "°F" : "°C", systemImage: "thermometer.medium") {
                    Picker("Units", selection: Binding(get: { settings.useFahrenheit }, set: { settings.useFahrenheit = $0 })) {
                        Text("Celsius (°C)").tag(false)
                        Text("Fahrenheit (°F)").tag(true)
                    }
                    .pickerStyle(.inline)
                }
            }
            if components.isEmpty && sensors.fans.isEmpty {
                ContentUnavailableView(
                    "No temperature sensors",
                    systemImage: "thermometer.medium.slash",
                    description: Text("This Mac doesn't expose any readable temperature sensors.")
                )
                .foregroundStyle(Fluent.textSecondary)
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                            ForEach(cards(sensors)) { card in
                                switch card {
                                case .live(let component):
                                    ComponentCard(
                                        component: component,
                                        history: monitor.temperatureHistory[component.component]?.values ?? [],
                                        fahrenheit: settings.useFahrenheit
                                    )
                                case .idle(let component):
                                    IdleComponentCard(component: component)
                                }
                            }
                            ForEach(sensors.fans) { fan in
                                FanCard(fan: fan, history: monitor.fanHistory[fan.id]?.values ?? [])
                            }
                        }
                        sensorList(sensors, query: state.searchText.trimmingCharacters(in: .whitespaces))
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private enum Card: Identifiable {
        case live(ComponentTemperature)
        case idle(SensorComponent)

        var id: SensorComponent {
            switch self {
            case .live(let component): return component.component
            case .idle(let component): return component
            }
        }
    }

    /// One card per component, in a stable order, including components that are powered down.
    private func cards(_ sensors: SensorSnapshot) -> [Card] {
        let live = Dictionary(uniqueKeysWithValues: sensors.components.map { ($0.component, $0) })
        return SensorComponent.allCases.filter { $0 != .other }.compactMap { component in
            if let reading = live[component] { return .live(reading) }
            return sensors.idleComponents.contains(component) ? .idle(component) : nil
        }
    }

    @ViewBuilder
    private func sensorList(_ sensors: SensorSnapshot, query: String) -> some View {
        let grouped = Dictionary(grouping: sensors.readings.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.source.localizedCaseInsensitiveContains(query)
                || $0.component.title.localizedCaseInsensitiveContains(query)
        }, by: \.component)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("All sensors")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Fluent.textPrimary)
                Text("\(sensors.readings.count)")
                    .font(.system(size: 12))
                    .foregroundStyle(Fluent.textSecondary)
                Spacer()
                Button(expanded.count == grouped.count ? "Collapse all" : "Expand all") {
                    expanded = expanded.count == grouped.count ? [] : Set(grouped.keys)
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
            }
            .padding(.bottom, 2)
            VStack(spacing: 0) {
                HStack {
                    Text("Sensor").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Current").frame(width: 80, alignment: .trailing)
                    Text("Min").frame(width: 70, alignment: .trailing)
                    Text("Max").frame(width: 70, alignment: .trailing)
                    Text("Source").frame(width: 130, alignment: .leading).padding(.leading, 14)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Fluent.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                Rectangle().fill(Fluent.divider).frame(height: 1)
                ForEach(SensorComponent.allCases.filter { grouped[$0] != nil }, id: \.self) { component in
                    let readings = grouped[component] ?? []
                    let isOpen = expanded.contains(component) || !query.isEmpty
                    Button {
                        if expanded.contains(component) { expanded.remove(component) } else { expanded.insert(component) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .rotationEffect(.degrees(isOpen ? 90 : 0))
                                .foregroundStyle(Fluent.textSecondary)
                                .frame(width: 12)
                            Image(systemName: component.symbol).foregroundStyle(Fluent.accent).frame(width: 18)
                            Text(component.title).foregroundStyle(Fluent.textPrimary)
                            Text("(\(readings.count))").foregroundStyle(Fluent.textSecondary)
                            Spacer()
                            let hottest = readings.map(\.celsius).max() ?? 0
                            Text(Fmt.temperature(hottest, fahrenheit: settings.useFahrenheit))
                                .monospacedDigit()
                                .foregroundStyle(TemperatureScale.color(hottest))
                                .frame(width: 80, alignment: .trailing)
                            Color.clear.frame(width: 284)
                        }
                        .font(.system(size: 12.5, weight: .medium))
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if isOpen {
                        ForEach(readings) { reading in
                            SensorRow(reading: reading, extremes: monitor.sensorExtremes[reading.id], fahrenheit: settings.useFahrenheit)
                        }
                    }
                    Rectangle().fill(Fluent.divider).frame(height: 1)
                }
            }
            .background(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).fill(Fluent.card))
            .overlay(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).strokeBorder(Fluent.cardStroke))
            .clipShape(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous))
        }
    }
}

/// Colour bands for temperatures: cool, warm, hot, very hot.
enum TemperatureScale {
    static func color(_ celsius: Double) -> Color {
        switch celsius {
        case ..<60: return Fluent.efficiency
        case ..<80: return Color(light: NSColor(srgbRed: 0.76, green: 0.55, blue: 0, alpha: 1), dark: NSColor(srgbRed: 1, green: 0.8, blue: 0.3, alpha: 1))
        case ..<95: return Color(light: NSColor(srgbRed: 0.85, green: 0.38, blue: 0.05, alpha: 1), dark: NSColor(srgbRed: 1, green: 0.6, blue: 0.3, alpha: 1))
        default: return ResourceColor.thermal
        }
    }

    /// 20–110 °C mapped to 0…1 for gauges.
    static func fraction(_ celsius: Double) -> Double { min(max((celsius - 20) / 90, 0), 1) }
}

private struct ThermalStateBadge: View {
    let state: Int
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(state == 0 ? Fluent.efficiency : (state == 1 ? Color.yellow : ResourceColor.thermal)).frame(width: 7, height: 7)
            Text("Thermal pressure: \(text)")
        }
        .font(.system(size: 12))
        .foregroundStyle(Fluent.textSecondary)
        .help("How hard macOS is working to keep the Mac cool")
    }
}

private struct ComponentCard: View {
    let component: ComponentTemperature
    let history: [Double]
    let fahrenheit: Bool

    var body: some View {
        let color = TemperatureScale.color(component.average)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: component.component.symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(Fluent.accent)
                    .frame(width: 20)
                Text(component.component.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Fluent.textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Fmt.temperature(component.average, fahrenheit: fahrenheit))
                    .font(.system(size: 26, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(color)
                Text(component.count > 1 ? "Hottest \(Fmt.temperature(component.hottest, fahrenheit: fahrenheit))" : "")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Fluent.textSecondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Fluent.subtleSelected)
                    Capsule().fill(color).frame(width: max(4, geometry.size.width * TemperatureScale.fraction(component.average)))
                }
            }
            .frame(height: 5)
            PerfGraph(
                series: [GraphSeries(values: history, color: color)],
                maxValue: max(100, (history.max() ?? 0) + 5),
                tint: color.opacity(0.6),
                showGrid: false
            )
            .frame(height: 44)
            Text(component.count == 1 ? "1 sensor" : "Average of \(component.count) sensors")
                .font(.system(size: 11))
                .foregroundStyle(Fluent.textTertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).fill(Fluent.card))
        .overlay(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).strokeBorder(Fluent.cardStroke))
    }
}

private struct IdleComponentCard: View {
    let component: SensorComponent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: component.symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(Fluent.accent)
                    .frame(width: 20)
                Text(component.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Fluent.textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            Text("Idle")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Fluent.textSecondary)
            Text("These cores are powered down, so they aren't reporting a temperature. Readings return as soon as they wake.")
                .font(.system(size: 11.5))
                .foregroundStyle(Fluent.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).fill(Fluent.card))
        .overlay(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).strokeBorder(Fluent.cardStroke))
    }
}

private struct FanCard: View {
    let fan: FanReading
    let history: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "fan")
                    .font(.system(size: 14))
                    .foregroundStyle(Fluent.accent)
                    .frame(width: 20)
                Text("Fan \(fan.id + 1)")
                    .font(.system(size: 13))
                    .foregroundStyle(Fluent.textPrimary)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Fmt.rpm(fan.rpm))
                    .font(.system(size: 26, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Fluent.textPrimary)
                if fan.rpm >= 1 {
                    Text("\(Int(fan.fraction * 100))% of range")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Fluent.textSecondary)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Fluent.subtleSelected)
                    Capsule().fill(Fluent.accent).frame(width: max(4, geometry.size.width * fan.fraction))
                }
            }
            .frame(height: 5)
            PerfGraph(
                series: [GraphSeries(values: history, color: Fluent.accent)],
                maxValue: max(fan.maximum, 1),
                tint: Fluent.accent.opacity(0.6),
                showGrid: false
            )
            .frame(height: 44)
            Text("Range \(Int(fan.minimum))–\(Int(fan.maximum)) RPM")
                .font(.system(size: 11))
                .foregroundStyle(Fluent.textTertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).fill(Fluent.card))
        .overlay(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).strokeBorder(Fluent.cardStroke))
    }
}

private struct SensorRow: View {
    let reading: SensorReading
    let extremes: ClosedRange<Double>?
    let fahrenheit: Bool
    @State private var hovering = false

    var body: some View {
        HStack {
            Text(reading.name)
                .foregroundStyle(Fluent.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 46)
            Text(Fmt.temperature(reading.celsius, fahrenheit: fahrenheit, decimals: 1))
                .foregroundStyle(TemperatureScale.color(reading.celsius))
                .frame(width: 80, alignment: .trailing)
            Text(extremes.map { Fmt.temperature($0.lowerBound, fahrenheit: fahrenheit, decimals: 1) } ?? "")
                .foregroundStyle(Fluent.textSecondary)
                .frame(width: 70, alignment: .trailing)
            Text(extremes.map { Fmt.temperature($0.upperBound, fahrenheit: fahrenheit, decimals: 1) } ?? "")
                .foregroundStyle(Fluent.textSecondary)
                .frame(width: 70, alignment: .trailing)
            Text(reading.source)
                .foregroundStyle(Fluent.textTertiary)
                .frame(width: 130, alignment: .leading)
                .padding(.leading, 14)
                .lineLimit(1)
        }
        .font(.system(size: 12))
        .monospacedDigit()
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(hovering ? Fluent.rowHover : .clear)
        .onHover { hovering = $0 }
    }
}
