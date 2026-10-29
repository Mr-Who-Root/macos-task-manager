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
}

/// Owns the samplers; only ever used from the monitor's serial queue.
final class SamplingEngine: @unchecked Sendable {
    private let processSampler = ProcessSampler()
    private let systemSampler = SystemSampler()

    func sample(apps: [AppRef], currentUID: UInt32, efficient: Set<String>) -> SampleResult {
        let processes = processSampler.sample(efficient: efficient)
        let system = systemSampler.sample()
        let nodes = ProcessTreeBuilder.build(processes, apps: apps, currentUID: currentUID)
        return SampleResult(processes: processes, nodes: nodes, system: system, energyAvailable: processSampler.energyAvailable)
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
    /// Bumped when background code-signature lookups finish so Publisher columns refresh.
    private(set) var publisherRevision = 0

    let appHistory = AppHistoryStore()
    let batteryLog = BatteryLog()

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
