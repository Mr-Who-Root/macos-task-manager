import Foundation

/// One thing that may be slowing the Mac down, in plain words, with what to do about it.
struct Finding: Identifiable, Hashable {
    enum Severity: Int, Comparable {
        case info, warning, critical
        static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    enum Action: Hashable {
        case endTask(pid: Int32)
        case efficiency(pid: Int32)
        case showDetails(pid: Int32)
        case openURL(String)
        case revealFile(String)
        case openPage(String)       // Page raw value
    }

    struct Button: Hashable {
        let title: String
        let action: Action
    }

    let id: String
    let severity: Severity
    let symbol: String
    let title: String
    let detail: String
    var buttons: [Button] = []
}

/// What the diagnosis looks at, gathered from the monitor.
struct DiagnosisInput {
    var nodes: [ProcNode]
    /// Recent overall CPU use, 0...1, oldest first.
    var cpuHistory: [Double]
    var memory: MemorySnapshot
    var diskFree: UInt64
    var diskTotal: UInt64
    /// Recent active time of the startup disk, 0...1.
    var diskActiveHistory: [Double]
    /// Recent GPU use, 0...1.
    var gpuHistory: [Double]
    var thermalState: Int
    var cpuTemperature: Double?
    var lowPowerMode: Bool
    var uptime: TimeInterval
    var batteryCondition: String?
    /// Saved samples of apps that stopped responding, by PID.
    var hangSamples: [Int32: String] = [:]
    /// Data uploaded today by the busiest uploader.
    var topUploadToday: (name: String, bytes: Double)?
}

enum Diagnosis {
    /// Background work macOS does on its own, which explains a busy CPU or disk.
    static let systemActivities: [(names: Set<String>, title: String, detail: String, symbol: String)] = [
        (["mds", "mds_stores", "mdworker", "mdworker_shared", "corespotlightd", "mdsync", "mdbulkimport"],
         "Spotlight is indexing", "Spotlight is updating its search index, which keeps the CPU and disk busy for a while after big changes. It finishes on its own.", "magnifyingglass"),
        (["backupd", "backupd-helper"],
         "Time Machine is backing up", "A backup is running. It slows down while you're using the Mac and finishes on its own.", "clock.arrow.circlepath"),
        (["photoanalysisd", "mediaanalysisd", "photolibraryd"],
         "Photos is analysing your library", "Photos looks for faces, objects and text in new pictures. It mostly runs while the Mac is idle and plugged in.", "photo.on.rectangle"),
        (["softwareupdated", "mobileassetd", "SoftwareUpdateNotificationManager", "installd"],
         "macOS is preparing an update", "An update is downloading or being prepared. It finishes on its own.", "arrow.down.circle"),
        (["cloudd", "bird", "fileproviderd"],
         "iCloud is syncing", "iCloud Drive or Photos is syncing files, which uses the network, disk and some CPU until it catches up.", "icloud"),
    ]

    /// An app counts as a CPU hog above this share of the whole machine, averaged over two minutes.
    static let cpuHogThreshold = 20.0

    static func findings(_ input: DiagnosisInput) -> [Finding] {
        var findings: [Finding] = []
        let byName = Dictionary(grouping: input.nodes, by: \.name)
        func node(named names: Set<String>) -> [ProcNode] { names.flatMap { byName[$0] ?? [] } }

        // Apps that stopped responding.
        for node in input.nodes where node.notResponding {
            var buttons = [Finding.Button(title: "End task", action: .endTask(pid: node.mainPID))]
            if let sample = node.pids.lazy.compactMap({ input.hangSamples[$0] }).first {
                buttons.append(Finding.Button(title: "Show sample", action: .revealFile(sample)))
            }
            findings.append(Finding(
                id: "hang:\(node.id)", severity: .critical, symbol: "exclamationmark.octagon.fill",
                title: "\(node.name) is not responding",
                detail: "It has stopped handling clicks and keys. You can wait to see if it recovers, or end it. Unsaved work in it may be lost.",
                buttons: buttons
            ))
        }

        // Overheating.
        let kernelTask = byName["kernel_task"]?.first
        if input.thermalState >= 1 {
            let hottest = input.nodes.filter { $0.name != "kernel_task" }.sorted { ($0.power, $0.cpu) > ($1.power, $1.cpu) }.prefix(2)
            let throttling = (kernelTask?.cpuTrend ?? 0) >= 10
            findings.append(Finding(
                id: "thermal", severity: input.thermalState >= 2 ? .critical : .warning, symbol: "thermometer.high",
                title: input.thermalState >= 2 ? "Your Mac is too hot and is running slower" : "Your Mac is getting warm",
                detail: (throttling ? "kernel_task is using CPU time to cool the Mac down by slowing other work. " : "")
                    + (hottest.isEmpty ? "" : "Working hardest: \(hottest.map(\.name).joined(separator: ", ")). ")
                    + "Give it some air and close what you don't need.",
                buttons: hottest.first.map { [Finding.Button(title: "Efficiency mode for \($0.name)", action: .efficiency(pid: $0.mainPID))] } ?? []
            ))
        }

        // Known background work.
        var explained: Set<String> = []
        for activity in systemActivities {
            let busy = node(named: activity.names).filter { $0.cpuTrend >= 5 || $0.diskRate >= 5_242_880 }
            guard !busy.isEmpty else { continue }
            busy.forEach { explained.insert($0.id) }
            findings.append(Finding(id: "activity:\(activity.title)", severity: .info, symbol: activity.symbol,
                                    title: activity.title, detail: activity.detail))
        }

        // Apps using a lot of CPU for a while.
        let skip: Set<String> = ["kernel_task", "Task Manager", "TaskManager"]
        let hogs = input.nodes
            .filter { $0.cpuTrend >= cpuHogThreshold && !explained.contains($0.id) && !skip.contains($0.name) && !$0.notResponding }
            .sorted { $0.cpuTrend > $1.cpuTrend }
        for hog in hogs.prefix(3) {
            findings.append(Finding(
                id: "cpu:\(hog.id)", severity: hog.cpuTrend >= 50 ? .critical : .warning, symbol: "cpu",
                title: "\(hog.name) is using a lot of the processor",
                detail: "It has averaged \(Int(hog.cpuTrend.rounded()))% of the CPU over the last two minutes, which leaves less for everything else.",
                buttons: [
                    Finding.Button(title: "Efficiency mode", action: .efficiency(pid: hog.mainPID)),
                    Finding.Button(title: "End task", action: .endTask(pid: hog.mainPID)),
                ]
            ))
        }
        let recentCPU = average(input.cpuHistory.suffix(30))
        if hogs.isEmpty && recentCPU >= 0.85 {
            let top = input.nodes.sorted { $0.cpu > $1.cpu }.prefix(3).map(\.name)
            findings.append(Finding(id: "cpu:busy", severity: .warning, symbol: "cpu",
                                    title: "The processor is very busy",
                                    detail: "It has been over 85% busy recently. Busiest now: \(top.joined(separator: ", "))."))
        }

        // Memory.
        let memory = input.memory
        let heavySwap = memory.total > 0 && Double(memory.swapUsed) > Double(memory.total) * 0.5
        if memory.pressure >= 2 || heavySwap {
            let top = input.nodes.sorted { $0.memory > $1.memory }.prefix(3)
            findings.append(Finding(
                id: "memory", severity: memory.pressure >= 4 ? .critical : .warning, symbol: "memorychip",
                title: "Memory is running low",
                detail: "macOS is compressing memory and swapping to disk (\(Fmt.bytes(memory.swapUsed)) of swap), which slows everything down. "
                    + "Using the most: " + top.map { "\($0.name) (\(Fmt.bytes($0.memory)))" }.joined(separator: ", ") + ".",
                buttons: top.prefix(2).map { Finding.Button(title: "End \($0.name)", action: .endTask(pid: $0.mainPID)) }
            ))
        }

        // Disk space and activity.
        if input.diskTotal > 0 {
            let fraction = Double(input.diskFree) / Double(input.diskTotal)
            if input.diskFree < 10_000_000_000 || fraction < 0.1 {
                findings.append(Finding(
                    id: "disk:full", severity: input.diskFree < 5_000_000_000 ? .critical : .warning, symbol: "internaldrive",
                    title: "Your startup disk is almost full",
                    detail: "Only \(Fmt.bytes(input.diskFree)) is free. macOS needs free space for swap, updates and caches, and slows down without it.",
                    buttons: [Finding.Button(title: "Storage settings", action: .openURL("x-apple.systempreferences:com.apple.settings.Storage"))]
                ))
            }
        }
        if average(input.diskActiveHistory.suffix(15)) >= 0.8 {
            let top = input.nodes.filter { !explained.contains($0.id) }.sorted { $0.diskRate > $1.diskRate }.prefix(2)
            findings.append(Finding(
                id: "disk:busy", severity: .warning, symbol: "internaldrive",
                title: "The disk is very busy",
                detail: "It has been over 80% busy recently, so apps wait to read and write."
                    + (top.isEmpty ? "" : " Busiest: " + top.map { "\($0.name) (\(Fmt.diskRate($0.diskRate)))" }.joined(separator: ", ") + "."),
                buttons: top.first.map { [Finding.Button(title: "Efficiency mode for \($0.name)", action: .efficiency(pid: $0.mainPID))] } ?? []
            ))
        }

        // GPU.
        if average(input.gpuHistory.suffix(15)) >= 0.9 {
            findings.append(Finding(id: "gpu", severity: .info, symbol: "cube.transparent",
                                    title: "The graphics processor is fully busy",
                                    detail: "Games, video, 3D and many windows on several displays all share the GPU. Closing some can make animations smoother."))
        }

        // Settings and state that trade speed for something else.
        if input.lowPowerMode {
            findings.append(Finding(id: "lowpower", severity: .info, symbol: "leaf",
                                    title: "Low Power Mode is on",
                                    detail: "It saves energy by running the Mac more slowly.",
                                    buttons: [Finding.Button(title: "Battery settings", action: .openURL("x-apple.systempreferences:com.apple.Battery-Settings.extension"))]))
        }
        if input.uptime >= 14 * 86_400 {
            findings.append(Finding(id: "uptime", severity: .info, symbol: "arrow.clockwise",
                                    title: "Your Mac hasn't restarted in \(Int(input.uptime / 86_400)) days",
                                    detail: "Restarting clears memory that apps have built up over time and installs pending updates."))
        }
        if let condition = input.batteryCondition, condition != "Normal" {
            findings.append(Finding(id: "battery", severity: .info, symbol: "battery.25percent",
                                    title: "The battery needs service",
                                    detail: "Its condition is \"\(condition)\". A worn battery can make macOS limit performance.",
                                    buttons: [Finding.Button(title: "Battery page", action: .openPage("battery"))]))
        }
        if let upload = input.topUploadToday, upload.bytes >= 1_000_000_000 {
            findings.append(Finding(id: "upload", severity: .info, symbol: "arrow.up.circle",
                                    title: "\(upload.name) has uploaded \(Fmt.bytes(upload.bytes)) today",
                                    detail: "Large uploads can slow your connection. That's expected for backups and cloud sync; otherwise check what it's sending.",
                                    buttons: [Finding.Button(title: "Data usage", action: .openPage("appHistory"))]))
        }

        return findings.enumerated().sorted { a, b in
            a.element.severity != b.element.severity ? a.element.severity > b.element.severity : a.offset < b.offset
        }.map(\.element)
    }

    private static func average<C: Collection>(_ values: C) -> Double where C.Element == Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}
