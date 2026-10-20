import AppKit
import TaskManagerShared
import WidgetKit

/// Shares a snapshot of the latest figures with the widget extension.
@MainActor
final class WidgetPublisher {
    static let shared = WidgetPublisher()

    private var lastWrite = Date.distantPast
    private var lastReload = Date.distantPast
    private var iconCache: [String: Data] = [:]
    private let queue = DispatchQueue(label: "TaskManager.widgets", qos: .utility)

    func publish(_ monitor: Monitor) {
        let now = Date()
        guard now.timeIntervalSince(lastWrite) >= 5 else { return }
        lastWrite = now
        let snapshot = makeSnapshot(monitor)
        queue.async {
            try? WidgetSnapshotStore.write(snapshot)
        }
        if now.timeIntervalSince(lastReload) >= 60 {
            lastReload = now
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func makeSnapshot(_ monitor: Monitor) -> WidgetSnapshot {
        let s = monitor.system
        let hw = HardwareInfo.shared
        let settings = AppSettings.shared
        let systemDisk = s.disks.first(where: \.isSystemDisk) ?? s.disks.first
        var fs = statfs()
        let hasRoot = statfs("/", &fs) == 0
        let topApps = monitor.nodes.sorted { $0.cpu > $1.cpu }.prefix(9).map {
            WidgetSnapshot.App(name: $0.name, cpu: $0.cpu, memory: $0.memory, icon: icon(for: $0.iconPath))
        }
        let temperatures = s.sensors.components.filter { $0.component != .other }.map {
            WidgetSnapshot.Temperature(name: $0.component.shortTitle, symbol: $0.component.symbol, celsius: $0.average)
        }
        // Put the CPU first so small widgets show the figure people expect.
        let cpuFirst = temperatures.sorted { a, b in
            let rank = { (name: String) -> Int in ["P-cores", "CPU", "E-cores", "SoC", "GPU"].firstIndex(of: name) ?? 9 }
            return rank(a.name) < rank(b.name)
        }
        func sum(_ histories: [String: History]) -> [Double] {
            let series = histories.values.map(\.values)
            let length = series.map(\.count).max() ?? 0
            var total = [Double](repeating: 0, count: length)
            for values in series {
                for (i, v) in values.enumerated() { total[length - values.count + i] += v }
            }
            return total
        }
        return WidgetSnapshot(
            date: Date(), design: DesignStore.shared.design.rawValue, accent: DesignStore.shared.accent.rawValue,
            fahrenheit: settings.useFahrenheit,
            cpu: s.cpu.total, cpuHistory: monitor.cpuHistory.values, perCore: s.cpu.perCore, cpuName: hw.cpuName,
            processCount: monitor.processes.count, threadCount: monitor.threadCount, uptime: Date().timeIntervalSince(hw.bootTime),
            memoryUsed: s.memory.used, memoryTotal: s.memory.total, memoryCompressed: s.memory.compressed,
            memoryCached: s.memory.cached, swapUsed: s.memory.swapUsed, memoryPressure: s.memory.pressureText,
            memoryHistory: monitor.memoryHistory.values,
            gpu: s.gpu?.utilization, gpuName: s.gpu?.name ?? hw.gpuName, gpuHistory: monitor.gpuHistory.values,
            diskName: systemDisk?.volumes.first ?? "Macintosh HD",
            diskTotal: hasRoot ? UInt64(fs.f_blocks) * UInt64(fs.f_bsize) : 0,
            diskFree: hasRoot ? UInt64(fs.f_bavail) * UInt64(fs.f_bsize) : 0,
            diskRead: s.disks.reduce(0) { $0 + $1.readRate }, diskWrite: s.disks.reduce(0) { $0 + $1.writeRate },
            networkSend: s.networks.reduce(0) { $0 + $1.sendRate } / 8,
            networkReceive: s.networks.reduce(0) { $0 + $1.receiveRate } / 8,
            networkSendHistory: sum(monitor.netSendHistory).map { $0 / 8 },
            networkReceiveHistory: sum(monitor.netReceiveHistory).map { $0 / 8 },
            topApps: Array(topApps), temperatures: cpuFirst, fans: s.sensors.fans.map(\.rpm), thermalState: s.sensors.thermalStateText
        )
    }

    /// 32×32 PNG of an app icon, cached by path.
    private func icon(for path: String?) -> Data? {
        guard let path else { return nil }
        if let cached = iconCache[path] { return cached }
        let source = IconCache.icon(for: path)
        let size = NSSize(width: 32, height: 32)
        let image = NSImage(size: size)
        image.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        iconCache[path] = png
        return png
    }
}

/// Handles taskmanager:// links from widgets, e.g. taskmanager://performance/cpu.
@MainActor
enum DeepLink {
    static func open(_ url: URL) {
        guard url.scheme == WidgetSnapshotStore.urlScheme else { return }
        let state = AppState.shared
        let parts = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" }).filter { !$0.isEmpty }
        switch parts.first {
        case "processes": state.page = .processes
        case "temperatures": state.page = .temperatures
        case "performance":
            state.page = .performance
            let system = Monitor.shared.system
            switch parts.dropFirst().first {
            case "cpu": state.perfItem = .cpu
            case "memory": state.perfItem = .memory
            case "gpu": state.perfItem = .gpu
            case "network": if let first = system.networks.first { state.perfItem = .network(first.id) }
            case "disk": if let first = system.disks.first(where: \.isSystemDisk) ?? system.disks.first { state.perfItem = .disk(first.id) }
            default: break
            }
        default: break
        }
        state.bringToFront()
    }
}
