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

enum MenuBarItem: String, CaseIterable, Identifiable {
    case cpu, memory, gpu, network, disk, temperature

    var id: String { rawValue }
    /// The UserDefaults key the menu bar scene binds `isInserted` to.
    var defaultsKey: String { "menubar.\(rawValue)" }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .gpu: return "GPU"
        case .network: return "Network"
        case .disk: return "Disk"
        case .temperature: return "Temperature"
        }
    }

    /// Prefix used when the menu bar shows values without icons.
    var shortLabel: String? {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "MEM"
        case .gpu: return "GPU"
        default: return nil
        }
    }

    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .gpu: return "cube.transparent"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .temperature: return "thermometer.medium"
        }
    }
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case iconAndValue, value, graph, meter

    var id: String { rawValue }
    var title: String {
        switch self {
        case .iconAndValue: return "Icon and value"
        case .value: return "Value only"
        case .graph: return "Icon and graph"
        case .meter: return "Icon and meter"
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
            DesignStore.applyAppearance()
        }
    }
    var alwaysOnTop: Bool {
        didSet {
            defaults.set(alwaysOnTop, forKey: "alwaysOnTop")
            AppState.shared.applyWindowLevel()
        }
    }
    /// Items shown in the menu bar, each persisted under its own key.
    var menuBarItems: Set<MenuBarItem> {
        didSet {
            guard menuBarItems != oldValue else { return }
            for item in MenuBarItem.allCases { defaults.set(menuBarItems.contains(item), forKey: item.defaultsKey) }
            MenuBarController.shared.sync()
        }
    }
    var menuBarStyle: MenuBarStyle {
        didSet {
            defaults.set(menuBarStyle.rawValue, forKey: "menuBarStyle")
            MenuBarController.shared.refresh()
        }
    }
    var globalHotKey: Bool {
        didSet {
            defaults.set(globalHotKey, forKey: "globalHotKey")
            GlobalHotKey.shared.setEnabled(globalHotKey)
        }
    }
    var useFahrenheit: Bool { didSet { defaults.set(useFahrenheit, forKey: "useFahrenheit") } }
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
        // Version 1.0 had a single "CPU in the menu bar" switch.
        if d.object(forKey: MenuBarItem.cpu.defaultsKey) == nil && d.bool(forKey: "showMenuBarCPU") {
            d.set(true, forKey: MenuBarItem.cpu.defaultsKey)
        }
        menuBarItems = Set(MenuBarItem.allCases.filter { d.bool(forKey: $0.defaultsKey) })
        menuBarStyle = MenuBarStyle(rawValue: d.string(forKey: "menuBarStyle") ?? "") ?? .iconAndValue
        globalHotKey = d.object(forKey: "globalHotKey") as? Bool ?? true
        autoCheckUpdates = d.object(forKey: "autoCheckUpdates") as? Bool ?? true
        useFahrenheit = d.object(forKey: "useFahrenheit") as? Bool ?? (Locale.current.measurementSystem == .us)
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

    func setMenuBarItem(_ item: MenuBarItem, shown: Bool) {
        if shown { menuBarItems.insert(item) } else { menuBarItems.remove(item) }
    }

    func width(of column: ProcColumn) -> CGFloat {
        columnWidths[column.rawValue].map { CGFloat($0) } ?? column.defaultWidth
    }

    func toggleColumn(_ column: ProcColumn) {
        if visibleColumns.contains(column) { visibleColumns.remove(column) } else { visibleColumns.insert(column) }
    }
}
