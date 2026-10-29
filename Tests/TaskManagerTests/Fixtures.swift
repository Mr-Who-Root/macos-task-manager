import Foundation
@testable import TaskManager

/// Builders for processes and app groups with only the figures a test cares about.
enum Fixtures {
    static func process(_ pid: Int32, _ name: String, cpu: Double = 0, memory: UInt64 = 0, notResponding: Bool = false) -> ProcessSample {
        var sample = ProcessSample(
            pid: pid, ppid: 1, uid: 501, user: "test", name: name, path: "/Applications/\(name).app/Contents/MacOS/\(name)",
            startTime: Date(timeIntervalSince1970: 1_000), state: .running, isTranslated: false, nice: 0, restricted: false
        )
        sample.cpu = cpu
        sample.memory = memory
        sample.notResponding = notResponding
        return sample
    }

    static func node(
        _ name: String, pid: Int32 = 100, kind: ProcKind = .app, cpu: Double = 0, cpuTrend: Double? = nil,
        memory: UInt64 = 0, diskRate: Double = 0, power: Double = 0, notResponding: Bool = false
    ) -> ProcNode {
        var node = ProcNode(
            id: "app:\(name):\(pid)", kind: kind, name: name, iconPath: nil, bundlePath: nil,
            mainPID: pid, isApp: kind == .app, historyKey: "/Applications/\(name).app",
            members: [process(pid, name, cpu: cpu, memory: memory, notResponding: notResponding)]
        )
        node.recalculate()
        node.cpuTrend = cpuTrend ?? cpu
        node.diskRate = diskRate
        node.power = power
        return node
    }

    static func diagnosis(nodes: [ProcNode] = [], memory: MemorySnapshot = MemorySnapshot()) -> DiagnosisInput {
        DiagnosisInput(
            nodes: nodes, cpuHistory: Array(repeating: 0.1, count: 30), memory: memory,
            diskFree: 300_000_000_000, diskTotal: 1_000_000_000_000, diskActiveHistory: Array(repeating: 0.05, count: 15),
            gpuHistory: Array(repeating: 0.1, count: 15), thermalState: 0, cpuTemperature: 45, lowPowerMode: false,
            uptime: 3_600, batteryCondition: "Normal"
        )
    }

    static func temporaryFile(_ name: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskManagerTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }
}
