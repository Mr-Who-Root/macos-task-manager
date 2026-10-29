import AppKit
import Foundation
import Observation

/// A fixed-length series of samples for the performance graphs (60 points, like Windows).
struct History: Sendable {
    static let capacity = 60
    private(set) var values: [Double] = []

    mutating func push(_ value: Double) {
        values.append(value)
        if values.count > Self.capacity { values.removeFirst(values.count - Self.capacity) }
    }

    var last: Double { values.last ?? 0 }
    var peak: Double { values.max() ?? 0 }
}

struct SampleResult: Sendable {
    let processes: [ProcessSample]
    let nodes: [ProcNode]
    let system: SystemSnapshot
    let energyAvailable: Bool
    let hangs: [Int32: HangDetector.Hang]
    /// Refreshed every few seconds; nil when unchanged since the last result.
    let listeningPorts: [ListeningPort]?
}

/// Owns the samplers; only ever used from the monitor's serial queue.
final class SamplingEngine: @unchecked Sendable {
    private let processSampler = ProcessSampler()
    private let systemSampler = SystemSampler()
    private let hangDetector = HangDetector()
    private var lastPortScan = Date.distantPast

    func sample(apps: [AppRef], currentUID: UInt32, efficient: Set<String>) -> SampleResult {
        var processes = processSampler.sample(efficient: efficient)
        let hangs = hangDetector.sample(apps.filter(\.isRegular).map(\.pid))
        if !hangs.isEmpty {
            for i in processes.indices where hangs[processes[i].pid] != nil { processes[i].notResponding = true }
        }
        let system = systemSampler.sample()
        let nodes = ProcessTreeBuilder.build(processes, apps: apps, currentUID: currentUID)
        var ports: [ListeningPort]?
        if Date().timeIntervalSince(lastPortScan) >= 10 {
            lastPortScan = Date()
            ports = NetworkPorts.listening()
        }
        return SampleResult(processes: processes, nodes: nodes, system: system, energyAvailable: processSampler.energyAvailable,
                            hangs: hangs, listeningPorts: ports)
    }
}

@Observable @MainActor
final class Monitor {
    static let shared = Monitor()

    private(set) var processes: [ProcessSample] = []
    private(set) var nodes: [ProcNode] = []
    private(set) var system = SystemSnapshot()
    private(set) var tick = 0

    private(set) var cpuHistory = History()
    private(set) var cpuKernelHistory = History()
    private(set) var coreHistory: [History] = []
    private(set) var coreKernelHistory: [History] = []
    private(set) var memoryHistory = History()
    private(set) var diskActiveHistory: [String: History] = [:]
    private(set) var diskReadHistory: [String: History] = [:]
    private(set) var diskWriteHistory: [String: History] = [:]
    private(set) var netSendHistory: [String: History] = [:]
    private(set) var netReceiveHistory: [String: History] = [:]
    private(set) var gpuHistory = History()
    private(set) var gpuRendererHistory = History()
    private(set) var gpuTilerHistory = History()
    private(set) var gpuMemoryHistory = History()
    private(set) var temperatureHistory: [SensorComponent: History] = [:]
    private(set) var fanHistory: [Int: History] = [:]
    /// Lowest and highest reading per sensor since Task Manager started.
    private(set) var sensorExtremes: [String: ClosedRange<Double>] = [:]
    private(set) var powerDrawHistory = History()
    private(set) var batteryTemperatureHistory = History()
    /// False on Macs that don't account energy per process (Intel); power usage is then estimated from CPU use.
    private(set) var energyAvailable = false
    /// Apps that have stopped responding, by PID.
    private(set) var hangs: [Int32: HangDetector.Hang] = [:]
    /// Diagnostic samples saved when apps stopped responding, by PID.
    private(set) var hangSamples: [Int32: String] = [:]
    private(set) var listeningPorts: [ListeningPort] = []
    /// Bumped when background code-signature lookups finish so Publisher columns refresh.
    private(set) var publisherRevision = 0

    let appHistory = AppHistoryStore()
    let batteryLog = BatteryLog()
    let timeline = TimelineStore()
    let dataUsage = DataUsageStore()
    let privacy = PrivacyMonitor()

    @ObservationIgnored private let engine = SamplingEngine()
    @ObservationIgnored private let queue = DispatchQueue(label: "TaskManager.sampling", qos: .userInitiated)
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var inFlight = false
    @ObservationIgnored private var started = false

    var threadCount: Int { processes.reduce(0) { $0 + $1.threads } }

    /// Time span covered by the 60-sample graphs.
    var graphSpan: Double { (AppSettings.shared.updateSpeed.interval ?? 1) * Double(History.capacity) }

    func process(_ pid: Int32) -> ProcessSample? {
        processes.first { $0.pid == pid }
    }

    func start() {
        guard !started else { return }
        started = true
        privacy.start()
        sampleNow()
        // A second quick sample gives every rate a baseline straight away.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            self.sampleNow()
            self.restartTimer()
        }
    }

    func restartTimer() {
        timer?.invalidate()
        timer = nil
        guard started, let interval = AppSettings.shared.updateSpeed.interval else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleNow() }
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refreshNow() {
        sampleNow()
    }

    func refreshSoon() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            self.sampleNow()
        }
    }

    private func sampleNow() {
        guard !inFlight else { return }
        inFlight = true
        let apps = NSWorkspace.shared.runningApplications.map {
            AppRef(pid: $0.processIdentifier, bundlePath: $0.bundleURL?.path, name: $0.localizedName ?? "", isRegular: $0.activationPolicy == .regular)
        }
        let uid = getuid()
        let engine = self.engine
        let efficient = EfficiencyStore.shared.keys
        queue.async {
            let result = engine.sample(apps: apps, currentUID: uid, efficient: efficient)
            Task { @MainActor in self.apply(result) }
        }
    }

    private func apply(_ result: SampleResult) {
        inFlight = false
        processes = result.processes
        nodes = result.nodes
        system = result.system
        tick += 1

        let s = result.system
        cpuHistory.push(s.cpu.total)
        cpuKernelHistory.push(s.cpu.kernel)
        var cores = coreHistory
        var coresKernel = coreKernelHistory
        if cores.count != s.cpu.perCore.count {
            cores = Array(repeating: History(), count: s.cpu.perCore.count)
            coresKernel = cores
        }
        for i in s.cpu.perCore.indices {
            cores[i].push(s.cpu.perCore[i])
            coresKernel[i].push(s.cpu.perCoreKernel[i])
        }
        coreHistory = cores
        coreKernelHistory = coresKernel
        memoryHistory.push(s.memory.usedFraction)

        var active = diskActiveHistory, read = diskReadHistory, write = diskWriteHistory
        for disk in s.disks {
            active[disk.id, default: History()].push(disk.activeTime)
            read[disk.id, default: History()].push(disk.readRate)
            write[disk.id, default: History()].push(disk.writeRate)
        }
        diskActiveHistory = active
        diskReadHistory = read
        diskWriteHistory = write

        var send = netSendHistory, receive = netReceiveHistory
        for net in s.networks {
            send[net.id, default: History()].push(net.sendRate)
            receive[net.id, default: History()].push(net.receiveRate)
        }
        netSendHistory = send
        netReceiveHistory = receive

        if let gpu = s.gpu {
            gpuHistory.push(gpu.utilization)
            gpuRendererHistory.push(gpu.renderer)
            gpuTilerHistory.push(gpu.tiler)
            gpuMemoryHistory.push(Double(gpu.memoryUsed))
        }

        var temperatures = temperatureHistory
        for component in s.sensors.components {
            temperatures[component.component, default: History()].push(component.average)
        }
        temperatureHistory = temperatures
        var fans = fanHistory
        for fan in s.sensors.fans { fans[fan.id, default: History()].push(fan.rpm) }
        fanHistory = fans
        var extremes = sensorExtremes
        for reading in s.sensors.readings {
            let value = reading.celsius
            if let range = extremes[reading.id] {
                extremes[reading.id] = min(range.lowerBound, value)...max(range.upperBound, value)
            } else {
                extremes[reading.id] = value...value
            }
        }
        sensorExtremes = extremes

        energyAvailable = result.energyAvailable
        recordActivity(result)
        if s.battery.isPresent {
            if let draw = s.battery.powerDraw { powerDrawHistory.push(draw) }
            if let celsius = batteryTemperature { batteryTemperatureHistory.push(celsius) }
            batteryLog.record(s.battery)
        }

        appHistory.record(result.nodes)
        EfficiencyStore.shared.reconcile(with: result.processes)
        WidgetPublisher.shared.publish(self)
        MenuBarController.shared.refresh()

        var paths = Set(result.processes.compactMap(\.path))
        paths.formUnion(result.nodes.compactMap(\.path))
        CodeSigning.prefetch(paths) { [weak self] in
            Task { @MainActor in self?.publisherRevision += 1 }
        }
    }

    // MARK: Timeline, data usage and hangs

    @ObservationIgnored private var lastThermalState = 0
    @ObservationIgnored private var lastPressure = 1

    private func recordActivity(_ result: SampleResult) {
        let s = result.system
        let names = Dictionary(result.processes.map { ($0.pid, $0.name) }, uniquingKeysWith: { a, _ in a })
        let appNames = Dictionary(result.nodes.flatMap { node in node.pids.map { ($0, node.name) } }, uniquingKeysWith: { a, _ in a })

        // Apps that just stopped responding: note it and keep a sample of what they're doing.
        for (pid, _) in result.hangs where hangs[pid] == nil {
            let name = appNames[pid] ?? names[pid] ?? "PID \(pid)"
            timeline.note("\(name) stopped responding")
            captureHangSample(pid: pid, name: name)
        }
        hangs = result.hangs
        hangSamples = hangSamples.filter { result.hangs[$0.key] != nil || names[$0.key] != nil }
        if let ports = result.listeningPorts { listeningPorts = ports }

        if s.sensors.thermalState != lastThermalState {
            if s.sensors.thermalState > 0 || lastThermalState > 0 { timeline.note("Thermal pressure: \(s.sensors.thermalStateText)") }
            lastThermalState = s.sensors.thermalState
        }
        if s.memory.pressure != lastPressure {
            if s.memory.pressure > 1 || lastPressure > 1 { timeline.note("Memory pressure: \(s.memory.pressureText)") }
            lastPressure = s.memory.pressure
        }

        timeline.record(TimelineStore.Sample(
            cpu: s.cpu.total,
            memory: s.memory.usedFraction,
            disk: s.disks.reduce(0) { $0 + $1.readRate + $1.writeRate },
            network: s.networks.reduce(0) { $0 + $1.sendRate + $1.receiveRate } / 8,
            power: s.battery.powerDraw,
            temperature: s.sensors.cpuTemperature,
            apps: result.nodes.map {
                (key: $0.historyKey, name: $0.name, cpu: $0.cpu, memory: $0.memory,
                 power: result.energyAvailable ? $0.power : nil, disk: $0.diskRate, network: $0.netRate)
            }
        ))
        dataUsage.record(result.nodes)
    }

    @ObservationIgnored private var lastSampled: [Int32: Date] = [:]

    private func captureHangSample(pid: Int32, name: String) {
        // One sample per app every few minutes is plenty, and sampling briefly pauses the app.
        if let last = lastSampled[pid], Date().timeIntervalSince(last) < 300 { return }
        lastSampled[pid] = Date()
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/TaskManager/Hangs", isDirectory: true)
        guard let logs else { return }
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "-")
        let safeName = name.replacingOccurrences(of: "/", with: "-")
        let file = logs.appendingPathComponent("\(safeName) \(stamp).txt")
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            Shell.run("/usr/bin/sample", [String(pid), "3", "-file", file.path])
            guard FileManager.default.fileExists(atPath: file.path) else { return }
            // Keep the 20 newest samples.
            let all = (try? FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            let sorted = all.sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }
            for old in sorted.dropFirst(20) { try? FileManager.default.removeItem(at: old) }
            await MainActor.run { self.hangSamples[pid] = file.path }
        }
    }

    /// Everything "Why is my Mac slow?" looks at.
    var diagnosisInput: DiagnosisInput {
        var fs = statfs()
        let hasDisk = statfs("/", &fs) == 0
        let systemDisk = system.disks.first(where: \.isSystemDisk) ?? system.disks.first
        let upload = dataUsage.totals(days: 1).max { $0.sent < $1.sent }
        return DiagnosisInput(
            nodes: nodes,
            cpuHistory: cpuHistory.values,
            memory: system.memory,
            diskFree: hasDisk ? UInt64(fs.f_bavail) * UInt64(fs.f_bsize) : 0,
            diskTotal: hasDisk ? UInt64(fs.f_blocks) * UInt64(fs.f_bsize) : 0,
            diskActiveHistory: systemDisk.flatMap { diskActiveHistory[$0.id]?.values } ?? [],
            gpuHistory: gpuHistory.values,
            thermalState: system.sensors.thermalState,
            cpuTemperature: system.sensors.cpuTemperature,
            lowPowerMode: system.battery.lowPowerMode,
            uptime: Date().timeIntervalSince(HardwareInfo.shared.bootTime),
            batteryCondition: system.battery.isPresent ? system.battery.condition : nil,
            hangSamples: hangSamples,
            topUploadToday: upload.map { ($0.name, $0.sent) }
        )
    }

    // MARK: Aggregates used by several pages

    /// Primary disk activity, shown in the Processes header.
    var diskActiveFraction: Double {
        (system.disks.first(where: \.isSystemDisk) ?? system.disks.first)?.activeTime ?? 0
    }

    /// The battery's own gas-gauge reading, or the battery sensors' average.
    var batteryTemperature: Double? {
        system.battery.temperature ?? system.sensors.components.first { $0.component == .battery }?.average
    }

    /// Throughput relative to link speed across active adapters, shown in the Processes header.
    var networkFraction: Double {
        let rate = system.networks.reduce(0) { $0 + $1.sendRate + $1.receiveRate }
        let capacity = system.networks.reduce(0.0) { $0 + Double($1.linkSpeed) }
        return rate / (capacity > 0 ? capacity : 1_000_000_000)
    }
}
