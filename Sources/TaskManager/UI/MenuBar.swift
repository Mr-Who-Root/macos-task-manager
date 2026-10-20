import AppKit
import SwiftUI

/// Values, scales and histories for each menu bar item.
@MainActor
enum MenuBarMetrics {
    struct Series {
        var values: [[Double]]
        var maxValue: Double
    }

    static func value(_ item: MenuBarItem, monitor: Monitor, fahrenheit: Bool) -> String {
        let s = monitor.system
        switch item {
        case .cpu: return Fmt.wholePercent(s.cpu.total)
        case .memory: return Fmt.wholePercent(s.memory.usedFraction)
        case .gpu: return Fmt.wholePercent(s.gpu?.utilization ?? 0)
        case .network: return "↑\(Fmt.compactRate(networkSend(monitor))) ↓\(Fmt.compactRate(networkReceive(monitor)))"
        case .disk: return "R \(Fmt.compactRate(diskRead(monitor))) W \(Fmt.compactRate(diskWrite(monitor)))"
        case .temperature:
            guard let celsius = s.sensors.cpuTemperature else { return "—" }
            let value = fahrenheit ? celsius * 9 / 5 + 32 : celsius
            return "\(Int(value.rounded()))°"
        }
    }

    /// Two short lines for items that show a pair of rates.
    static func lines(_ item: MenuBarItem, monitor: Monitor) -> [String]? {
        switch item {
        case .network: return ["↑ \(Fmt.compactRate(networkSend(monitor)))", "↓ \(Fmt.compactRate(networkReceive(monitor)))"]
        case .disk: return ["R \(Fmt.compactRate(diskRead(monitor)))", "W \(Fmt.compactRate(diskWrite(monitor)))"]
        default: return nil
        }
    }

    static func fraction(_ item: MenuBarItem, monitor: Monitor) -> Double {
        let s = monitor.system
        switch item {
        case .cpu: return s.cpu.total
        case .memory: return s.memory.usedFraction
        case .gpu: return s.gpu?.utilization ?? 0
        case .network: return monitor.networkFraction
        case .disk: return monitor.diskActiveFraction
        case .temperature: return TemperatureScale.fraction(s.sensors.cpuTemperature ?? 20)
        }
    }

    static func series(_ item: MenuBarItem, monitor: Monitor) -> Series {
        switch item {
        case .cpu: return Series(values: [monitor.cpuHistory.values], maxValue: 1)
        case .memory: return Series(values: [monitor.memoryHistory.values], maxValue: 1)
        case .gpu: return Series(values: [monitor.gpuHistory.values], maxValue: 1)
        case .network:
            let receive = sum(monitor.netReceiveHistory.values.map(\.values))
            let send = sum(monitor.netSendHistory.values.map(\.values))
            return Series(values: [receive, send], maxValue: Fmt.niceCeiling(max(receive.max() ?? 0, send.max() ?? 0), minimum: 100_000))
        case .disk:
            let read = sum(monitor.diskReadHistory.values.map(\.values))
            let write = sum(monitor.diskWriteHistory.values.map(\.values))
            return Series(values: [read, write], maxValue: Fmt.niceCeiling(max(read.max() ?? 0, write.max() ?? 0), minimum: 1_048_576))
        case .temperature:
            let cpu = [SensorComponent.cpuPerformance, .cpuEfficiency, .cpu, .soc]
                .compactMap { monitor.temperatureHistory[$0]?.values }
                .max { ($0.last ?? 0) < ($1.last ?? 0) } ?? []
            return Series(values: [cpu], maxValue: 100)
        }
    }

    static func networkSend(_ monitor: Monitor) -> Double { monitor.system.networks.reduce(0) { $0 + $1.sendRate } / 8 }
    static func networkReceive(_ monitor: Monitor) -> Double { monitor.system.networks.reduce(0) { $0 + $1.receiveRate } / 8 }
    static func diskRead(_ monitor: Monitor) -> Double { monitor.system.disks.reduce(0) { $0 + $1.readRate } }
    static func diskWrite(_ monitor: Monitor) -> Double { monitor.system.disks.reduce(0) { $0 + $1.writeRate } }

    /// Adds histories of equal capacity element-wise, aligned to the newest sample.
    private static func sum(_ histories: [[Double]]) -> [Double] {
        let length = histories.map(\.count).max() ?? 0
        guard length > 0 else { return [] }
        var total = [Double](repeating: 0, count: length)
        for history in histories {
            let offset = length - history.count
            for (i, v) in history.enumerated() { total[offset + i] += v }
        }
        return total
    }
}

// MARK: - Status items

/// Owns one NSStatusItem per enabled menu bar item and the pop-over they open.
/// (Several SwiftUI MenuBarExtra scenes bound to UserDefaults kept re-triggering each other.)
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    static let shared = MenuBarController()

    private var statusItems: [MenuBarItem: NSStatusItem] = [:]
    private var visibilityObservers: [NSKeyValueObservation] = []
    private let popover = NSPopover()
    private var popoverItem: MenuBarItem?

    private override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    /// Adds and removes status items to match Settings.
    func sync() {
        let wanted = AppSettings.shared.menuBarItems
        guard Set(statusItems.keys) != wanted else { return }
        // Recreate in a fixed order; macOS remembers positions by autosave name.
        visibilityObservers.removeAll()
        for item in statusItems.values { NSStatusBar.system.removeStatusItem(item) }
        statusItems.removeAll()
        for item in MenuBarItem.allCases.reversed() where wanted.contains(item) {
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem.autosaveName = "TaskManager.\(item.rawValue)"
            statusItem.behavior = .removalAllowed
            statusItem.isVisible = true
            if let button = statusItem.button {
                button.target = self
                button.action = #selector(toggle(_:))
                button.tag = MenuBarItem.allCases.firstIndex(of: item) ?? 0
                button.setAccessibilityLabel("Task Manager \(item.title)")
            }
            // Command-dragging an item out of the menu bar turns it off in Settings.
            visibilityObservers.append(statusItem.observe(\.isVisible, options: [.new]) { _, change in
                if change.newValue == false {
                    Task { @MainActor in AppSettings.shared.setMenuBarItem(item, shown: false) }
                }
            })
            statusItems[item] = statusItem
        }
        refresh()
    }

    /// Redraws every status item; called after each sample.
    func refresh() {
        guard !statusItems.isEmpty else { return }
        let monitor = Monitor.shared
        let settings = AppSettings.shared
        for (item, statusItem) in statusItems {
            statusItem.button?.image = MenuBarRenderer.image(item, style: settings.menuBarStyle, monitor: monitor, fahrenheit: settings.useFahrenheit)
            statusItem.button?.toolTip = "\(item.title): \(MenuBarMetrics.value(item, monitor: monitor, fahrenheit: settings.useFahrenheit))"
        }
    }

    @objc private func toggle(_ sender: NSStatusBarButton) {
        let item = MenuBarItem.allCases[sender.tag]
        if popover.isShown {
            popover.performClose(nil)
            if popoverItem == item { return }
        }
        let panel = MenuBarPanel(item: item)
            .environment(Monitor.shared)
            .environment(AppSettings.shared)
            .environment(AppState.shared)
        let host = NSHostingController(rootView: panel)
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popoverItem = item
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePopover() {
        popover.performClose(nil)
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            self.popoverItem = nil
            self.popover.contentViewController = nil
        }
    }
}

/// Draws the menu bar images with AppKit. They are template images, so macOS tints them
/// for light and dark menu bars. (Rendering SwiftUI views every second cost ~12% CPU.)
@MainActor
enum MenuBarRenderer {
    private static let height: CGFloat = 18

    static func image(_ item: MenuBarItem, style: MenuBarStyle, monitor: Monitor, fahrenheit: Bool) -> NSImage {
        let value = MenuBarMetrics.value(item, monitor: monitor, fahrenheit: fahrenheit)
        let lines = MenuBarMetrics.lines(item, monitor: monitor)
        let series = MenuBarMetrics.series(item, monitor: monitor)
        let fraction = MenuBarMetrics.fraction(item, monitor: monitor)
        let label = style == .value ? item.shortLabel : nil

        let symbol = style == .value ? nil : NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let lineFont = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold)
        let labelFont = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        func text(_ string: String, _ font: NSFont) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: NSColor.black])
        }
        let labelText = label.map { text($0, labelFont) }
        let valueText = text(value, valueFont)
        let lineTexts = (lines ?? []).map { text($0, lineFont) }

        // Measure the content to the right of the icon.
        let contentWidth: CGFloat
        switch style {
        case .graph: contentWidth = 34
        case .meter: contentWidth = 31
        case .iconAndValue, .value:
            if !lineTexts.isEmpty {
                contentWidth = max(38, lineTexts.map { ceil($0.size().width) }.max() ?? 0)
            } else {
                contentWidth = max(30, ceil(valueText.size().width)) + (labelText.map { ceil($0.size().width) + 3 } ?? 0)
            }
        }
        let iconWidth: CGFloat = symbol.map { ceil($0.size.width) + 3 } ?? 0
        let size = NSSize(width: iconWidth + contentWidth + 2, height: height)

        let image = NSImage(size: size, flipped: false) { _ in
            if let symbol {
                symbol.draw(in: NSRect(x: 1, y: (height - symbol.size.height) / 2, width: symbol.size.width, height: symbol.size.height))
            }
            let x = 1 + iconWidth
            switch style {
            case .graph:
                drawGraph(series.values.first ?? [], maxValue: series.maxValue, in: NSRect(x: x, y: 2, width: 34, height: 14))
            case .meter:
                drawMeter(fraction, in: NSRect(x: x, y: (height - 9) / 2, width: 31, height: 9))
            case .iconAndValue, .value:
                if !lineTexts.isEmpty {
                    for (index, line) in lineTexts.enumerated() {
                        line.draw(at: NSPoint(x: x, y: index == 0 ? height / 2 - 0.5 : 0.5))
                    }
                } else {
                    var cursor = x
                    if let labelText {
                        labelText.draw(at: NSPoint(x: cursor, y: (height - labelText.size().height) / 2))
                        cursor += ceil(labelText.size().width) + 3
                    }
                    let valueWidth = ceil(valueText.size().width)
                    valueText.draw(at: NSPoint(x: max(cursor, x + contentWidth - valueWidth), y: (height - valueText.size().height) / 2))
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "\(item.title) \(value)"
        return image
    }

    private static func drawGraph(_ history: [Double], maxValue: Double, in rect: NSRect) {
        NSColor.black.withAlphaComponent(0.5).setStroke()
        let frame = NSBezierPath(rect: rect.insetBy(dx: 0.25, dy: 0.25))
        frame.lineWidth = 0.5
        frame.stroke()
        let values = Array(history.suffix(30))
        guard values.count > 1 else { return }
        let scale = max(maxValue, 0.0001)
        let line = NSBezierPath()
        for (i, v) in values.enumerated() {
            let point = NSPoint(
                x: rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1),
                y: rect.minY + rect.height * CGFloat(min(max(v / scale, 0), 1))
            )
            i == 0 ? line.move(to: point) : line.line(to: point)
        }
        let fill = line.copy() as! NSBezierPath
        fill.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        fill.line(to: NSPoint(x: rect.minX, y: rect.minY))
        fill.close()
        NSColor.black.withAlphaComponent(0.35).setFill()
        fill.fill()
        NSColor.black.setStroke()
        line.lineWidth = 1
        line.stroke()
    }

    private static func drawMeter(_ fraction: Double, in rect: NSRect) {
        let radius = rect.height / 2
        NSColor.black.setStroke()
        let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        outline.lineWidth = 1
        outline.stroke()
        let inner = rect.insetBy(dx: 2, dy: 2)
        let width = max(inner.height, inner.width * CGFloat(min(max(fraction, 0), 1)))
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: width, height: inner.height),
                     xRadius: inner.height / 2, yRadius: inner.height / 2).fill()
    }
}

// MARK: - Panel

/// The pop-over shown when a menu bar item is clicked.
struct MenuBarPanel: View {
    let item: MenuBarItem
    @Environment(Monitor.self) private var monitor
    @Environment(AppState.self) private var state
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let design = Fluent.design
        let tint = tintColor
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: item.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(tint)
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(headline)
                    .font(.system(size: 20, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(Fluent.textPrimary)

            let series = MenuBarMetrics.series(item, monitor: monitor)
            PerfGraph(
                series: series.values.enumerated().map { index, values in
                    GraphSeries(values: values, color: tint, fillOpacity: index == 0 ? nil : 0, dashed: index > 0)
                },
                maxValue: series.maxValue,
                tint: tint,
                phase: monitor.tick,
                gridRows: 4,
                gridColumns: 10
            )
            .frame(height: 72)

            KeyValueGrid(rows: details)

            if !topProcesses.isEmpty {
                Rectangle().fill(Fluent.divider).frame(height: 1)
                Text(item == .temperature ? "Components" : "Top apps")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Fluent.textSecondary)
                VStack(spacing: 6) {
                    ForEach(topProcesses, id: \.name) { row in
                        HStack(spacing: 8) {
                            if let symbol = row.symbol {
                                Image(systemName: symbol).foregroundStyle(Fluent.accent).frame(width: 16)
                            } else {
                                ProcessIcon(path: row.icon).frame(width: 16, height: 16)
                            }
                            Text(row.name).lineLimit(1).foregroundStyle(Fluent.textPrimary)
                            Spacer()
                            Text(row.value).monospacedDigit().foregroundStyle(Fluent.textSecondary)
                        }
                        .font(.system(size: 12))
                    }
                }
            }

            Rectangle().fill(Fluent.divider).frame(height: 1)
            HStack(spacing: 6) {
                Button {
                    openPage()
                } label: {
                    Label("Open Task Manager", systemImage: "macwindow")
                }
                .buttonStyle(AccentButtonStyle())
                Spacer()
                Button {
                    state.page = .settings
                    state.bringToFront()
                    MenuBarController.shared.closePopover()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(SubtleButtonStyle(height: 28, horizontalPadding: 8))
                .help("Menu bar settings")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(SubtleButtonStyle(height: 28, horizontalPadding: 8))
                .help("Quit Task Manager")
            }
        }
        .padding(14)
        .frame(width: 310)
        .background(DesignBackground(design: design))
        .fontDesign(design.fontDesign == .default ? nil : design.fontDesign)
    }

    private var tintColor: Color {
        switch item {
        case .cpu: return ResourceColor.cpu
        case .memory: return ResourceColor.memory
        case .gpu: return ResourceColor.gpu
        case .network: return ResourceColor.network
        case .disk: return ResourceColor.disk
        case .temperature: return TemperatureScale.color(monitor.system.sensors.cpuTemperature ?? 40)
        }
    }

    private var headline: String {
        switch item {
        case .network, .disk: return Fmt.wholePercent(MenuBarMetrics.fraction(item, monitor: monitor))
        case .temperature:
            return monitor.system.sensors.cpuTemperature.map { Fmt.temperature($0, fahrenheit: settings.useFahrenheit) } ?? "—"
        default: return MenuBarMetrics.value(item, monitor: monitor, fahrenheit: settings.useFahrenheit)
        }
    }

    private var details: [(String, String)] {
        let s = monitor.system
        let hw = HardwareInfo.shared
        switch item {
        case .cpu:
            return [("Processor", hw.cpuName), ("Processes", "\(monitor.processes.count)"), ("Threads", "\(monitor.threadCount)"),
                    ("Load average", String(format: "%.2f", s.cpu.loadAverage)), ("Up time", Fmt.uptime(Date().timeIntervalSince(hw.bootTime)))]
        case .memory:
            return [("In use", "\(Fmt.gigabytes(s.memory.used)) of \(Fmt.gigabytes(s.memory.total))"), ("Compressed", Fmt.gigabytes(s.memory.compressed)),
                    ("Cached", Fmt.gigabytes(s.memory.cached)), ("Swap used", Fmt.gigabytes(s.memory.swapUsed)), ("Pressure", s.memory.pressureText)]
        case .gpu:
            return [("GPU", s.gpu?.name ?? hw.gpuName), ("Renderer", Fmt.wholePercent(s.gpu?.renderer ?? 0)), ("Tiler", Fmt.wholePercent(s.gpu?.tiler ?? 0)),
                    ("Shared memory", Fmt.gigabytes(s.gpu?.memoryUsed ?? 0))]
        case .network:
            var rows: [(String, String)] = [("Send", Fmt.bitRate(MenuBarMetrics.networkSend(monitor) * 8)),
                                            ("Receive", Fmt.bitRate(MenuBarMetrics.networkReceive(monitor) * 8))]
            for net in s.networks.prefix(2) {
                rows.append((net.name, net.ipv4.first ?? net.ipv6.first ?? net.id))
            }
            return rows
        case .disk:
            var rows: [(String, String)] = [("Read", Fmt.byteRate(MenuBarMetrics.diskRead(monitor))), ("Write", Fmt.byteRate(MenuBarMetrics.diskWrite(monitor)))]
            if let disk = s.disks.first(where: \.isSystemDisk) ?? s.disks.first {
                rows.append(("Disk", disk.title))
                rows.append(("Response time", String(format: "%.1f ms", disk.responseTimeMs)))
            }
            return rows
        case .temperature:
            var rows: [(String, String)] = [("Thermal pressure", s.sensors.thermalStateText)]
            for fan in s.sensors.fans {
                rows.append(("Fan \(fan.id + 1)", Fmt.rpm(fan.rpm)))
            }
            return rows
        }
    }

    private struct ListRow {
        let name: String
        let icon: String?
        var symbol: String?
        let value: String
    }

    private var topProcesses: [ListRow] {
        let nodes = monitor.nodes
        switch item {
        case .cpu:
            return nodes.sorted { $0.cpu > $1.cpu }.prefix(5).map { ListRow(name: $0.name, icon: $0.iconPath, value: Fmt.percent($0.cpu)) }
        case .memory:
            return nodes.sorted { $0.memory > $1.memory }.prefix(5).map { ListRow(name: $0.name, icon: $0.iconPath, value: Fmt.megabytes($0.memory)) }
        case .network:
            return nodes.filter { $0.netRate > 0 }.sorted { $0.netRate > $1.netRate }.prefix(5)
                .map { ListRow(name: $0.name, icon: $0.iconPath, value: Fmt.byteRate($0.netRate)) }
        case .disk:
            return nodes.filter { $0.diskRate > 0 }.sorted { $0.diskRate > $1.diskRate }.prefix(5)
                .map { ListRow(name: $0.name, icon: $0.iconPath, value: Fmt.byteRate($0.diskRate)) }
        case .temperature:
            return monitor.system.sensors.components.filter { $0.component != .other }.prefix(6).map {
                ListRow(name: $0.component.title, icon: nil, symbol: $0.component.symbol,
                        value: Fmt.temperature($0.average, fahrenheit: settings.useFahrenheit))
            }
        case .gpu:
            return []
        }
    }

    private func openPage() {
        switch item {
        case .cpu: state.perfItem = .cpu
        case .memory: state.perfItem = .memory
        case .gpu: state.perfItem = .gpu
        case .network: if let first = monitor.system.networks.first { state.perfItem = .network(first.id) }
        case .disk: if let first = monitor.system.disks.first { state.perfItem = .disk(first.id) }
        case .temperature: break
        }
        state.page = item == .temperature ? .temperatures : .performance
        state.bringToFront()
        MenuBarController.shared.closePopover()
    }
}
