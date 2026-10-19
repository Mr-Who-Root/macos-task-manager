import AppKit
import Observation

enum UpdateSpeed: String, CaseIterable, Identifiable {
    case high, normal, low, paused

    var id: String { rawValue }
    var title: String {
        switch self {
        case .high: return "High"
        case .normal: return "Normal"
        case .low: return "Low"
        case .paused: return "Paused"
        }
    }
    var interval: Double? {
        switch self {
        case .high: return 0.5
        case .normal: return 1
        case .low: return 4
        case .paused: return nil
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Use system setting"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    @MainActor func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum CPUGraphMode: String {
    case overall, logical
}

/// Columns of the Processes tab (Users reuses a subset).
enum ProcColumn: String, CaseIterable, Identifiable {
    case name, status, publisher, pid, processName, user, threads, architecture, cpu, memory, disk, network

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Name"
        case .status: return "Status"
        case .publisher: return "Publisher"
        case .pid: return "PID"
        case .processName: return "Process name"
        case .user: return "User name"
        case .threads: return "Threads"
        case .architecture: return "Architecture"
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .network: return "Network"
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .name: return 280
        case .status: return 120
        case .publisher: return 150
        case .pid: return 64
        case .processName: return 170
        case .user: return 110
        case .threads: return 70
        case .architecture: return 110
        case .cpu: return 76
        case .memory: return 100
        case .disk: return 90
        case .network: return 90
        }
    }

    var isNumeric: Bool { [.pid, .threads, .cpu, .memory, .disk, .network].contains(self) }
    var isOptional: Bool { ![.name, .cpu, .memory, .disk, .network].contains(self) }
    var sortsDescendingFirst: Bool { isNumeric && self != .pid }

    static let defaultVisible: Set<ProcColumn> = [.name, .status, .cpu, .memory, .disk, .network]
}

@Observable @MainActor
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let defaults = UserDefaults.standard

    var defaultPage: Page { didSet { defaults.set(defaultPage.rawValue, forKey: "defaultPage") } }
    var updateSpeed: UpdateSpeed {
        didSet {
            defaults.set(updateSpeed.rawValue, forKey: "updateSpeed")
            Monitor.shared.restartTimer()
        }
    }
    var theme: AppTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: "theme")
            theme.apply()
        }
    }
    var alwaysOnTop: Bool {
        didSet {
            defaults.set(alwaysOnTop, forKey: "alwaysOnTop")
            AppState.shared.applyWindowLevel()
        }
    }
    var showMenuBarCPU: Bool { didSet { defaults.set(showMenuBarCPU, forKey: "showMenuBarCPU") } }
    var globalHotKey: Bool {
        didSet {
            defaults.set(globalHotKey, forKey: "globalHotKey")
            GlobalHotKey.shared.setEnabled(globalHotKey)
        }
    }
    var autoCheckUpdates: Bool { didSet { defaults.set(autoCheckUpdates, forKey: "autoCheckUpdates") } }
    var showFullAccountName: Bool { didSet { defaults.set(showFullAccountName, forKey: "showFullAccountName") } }
    var historyAllProcesses: Bool { didSet { defaults.set(historyAllProcesses, forKey: "historyAllProcesses") } }
    var groupByType: Bool { didSet { defaults.set(groupByType, forKey: "groupByType") } }
    var navExpanded: Bool { didSet { defaults.set(navExpanded, forKey: "navExpanded") } }
    var showKernelTimes: Bool { didSet { defaults.set(showKernelTimes, forKey: "showKernelTimes") } }
    var cpuGraphMode: CPUGraphMode { didSet { defaults.set(cpuGraphMode.rawValue, forKey: "cpuGraphMode") } }
    var visibleColumns: Set<ProcColumn> { didSet { defaults.set(visibleColumns.map(\.rawValue), forKey: "visibleColumns") } }
    var columnWidths: [String: Double] { didSet { defaults.set(columnWidths, forKey: "columnWidths") } }

    private init() {
        let d = UserDefaults.standard
        defaultPage = Page(rawValue: d.string(forKey: "defaultPage") ?? "") ?? .processes
        updateSpeed = UpdateSpeed(rawValue: d.string(forKey: "updateSpeed") ?? "") ?? .normal
        theme = AppTheme(rawValue: d.string(forKey: "theme") ?? "") ?? .system
        alwaysOnTop = d.bool(forKey: "alwaysOnTop")
        showMenuBarCPU = d.bool(forKey: "showMenuBarCPU")
        globalHotKey = d.object(forKey: "globalHotKey") as? Bool ?? true
        autoCheckUpdates = d.object(forKey: "autoCheckUpdates") as? Bool ?? true
        showFullAccountName = d.bool(forKey: "showFullAccountName")
        historyAllProcesses = d.bool(forKey: "historyAllProcesses")
        groupByType = d.object(forKey: "groupByType") as? Bool ?? true
        navExpanded = d.object(forKey: "navExpanded") as? Bool ?? true
        showKernelTimes = d.bool(forKey: "showKernelTimes")
        cpuGraphMode = CPUGraphMode(rawValue: d.string(forKey: "cpuGraphMode") ?? "") ?? .overall
        if let stored = d.stringArray(forKey: "visibleColumns") {
            visibleColumns = Set(stored.compactMap(ProcColumn.init(rawValue:))).union([.name])
        } else {
            visibleColumns = ProcColumn.defaultVisible
        }
        columnWidths = d.dictionary(forKey: "columnWidths") as? [String: Double] ?? [:]
    }

    func width(of column: ProcColumn) -> CGFloat {
        columnWidths[column.rawValue].map { CGFloat($0) } ?? column.defaultWidth
    }

    func toggleColumn(_ column: ProcColumn) {
        if visibleColumns.contains(column) { visibleColumns.remove(column) } else { visibleColumns.insert(column) }
    }
}
