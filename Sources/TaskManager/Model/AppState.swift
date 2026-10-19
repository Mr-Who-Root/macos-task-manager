import AppKit
import Observation
import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case processes, performance, appHistory, startup, users, details, services, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .processes: return "Processes"
        case .performance: return "Performance"
        case .appHistory: return "App history"
        case .startup: return "Startup apps"
        case .users: return "Users"
        case .details: return "Details"
        case .services: return "Services"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .processes: return "square.grid.2x2"
        case .performance: return "waveform.path.ecg"
        case .appHistory: return "clock.arrow.circlepath"
        case .startup: return "gauge.with.dots.needle.33percent"
        case .users: return "person.2"
        case .details: return "list.bullet"
        case .services: return "puzzlepiece.extension"
        case .settings: return "gearshape"
        }
    }

    var shortcut: KeyEquivalent {
        KeyEquivalent(Character(String((Page.allCases.firstIndex(of: self) ?? 0) + 1)))
    }
}

enum PerfItem: Hashable {
    case cpu, memory, gpu
    case disk(String)
    case network(String)

    var storageValue: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memory"
        case .gpu: return "gpu"
        case .disk(let id): return "disk:\(id)"
        case .network(let id): return "network:\(id)"
        }
    }

    init(storageValue: String?) {
        let parts = (storageValue ?? "").split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first, parts.count > 1 ? parts[1] : "") {
        case ("memory", _): self = .memory
        case ("gpu", _): self = .gpu
        case ("disk", let id) where !id.isEmpty: self = .disk(id)
        case ("network", let id) where !id.isEmpty: self = .network(id)
        default: self = .cpu
        }
    }
}

struct AppAlert: Identifiable {
    struct Action {
        let title: String
        var role: ButtonRole?
        let perform: () -> Void
    }

    let id = UUID()
    let title: String
    let message: String
    var action: Action?
}

struct PropertiesTarget: Identifiable {
    let pid: Int32
    var id: Int32 { pid }
}

/// UI state shared between the window, menus and pages.
@Observable @MainActor
final class AppState {
    static let shared = AppState()
    static let mainWindowID = "main"

    var page: Page = AppSettings.shared.defaultPage
    var perfItem = PerfItem(storageValue: UserDefaults.standard.string(forKey: "perfItem")) {
        didSet { UserDefaults.standard.set(perfItem.storageValue, forKey: "perfItem") }
    }
    var searchText = ""
    var showRunTask = false
    var properties: PropertiesTarget?
    var alert: AppAlert?
    var detailsFocusPID: Int32?
    var searchFocusRequest = 0
    var endTaskRequest = 0
    var titleBarHeight: CGFloat = 48
    var titleBarLeadingInset: CGFloat = 80

    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored var openMainWindow: (() -> Void)?

    func showDetails(for pid: Int32) {
        detailsFocusPID = pid
        page = .details
    }

    func applyWindowLevel() {
        window?.level = AppSettings.shared.alwaysOnTop ? .floating : .normal
    }

    func bringToFront() {
        NSApp.activate()
        if let window, window.isVisible || window.isMiniaturized {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
    }

    /// Makes the native title bar transparent and taller so the custom
    /// Windows-style title bar can sit in it with the traffic lights centred.
    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        if window.toolbar == nil {
            let toolbar = NSToolbar(identifier: "TaskManagerTitleBar")
            window.toolbar = toolbar
        }
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenPrimary)
        applyWindowLevel()
        Task { @MainActor in
            self.measureTitleBar(window)
        }
    }

    private func measureTitleBar(_ window: NSWindow) {
        guard let close = window.standardWindowButton(.closeButton),
              let zoom = window.standardWindowButton(.zoomButton),
              let content = window.contentView else { return }
        let closeFrame = close.convert(close.bounds, to: content)
        let zoomFrame = zoom.convert(zoom.bounds, to: content)
        let centerFromTop = content.isFlipped ? closeFrame.midY : content.bounds.height - closeFrame.midY
        if centerFromTop > 0 && centerFromTop < 60 {
            titleBarHeight = max(40, (centerFromTop * 2).rounded())
            titleBarLeadingInset = zoomFrame.maxX + 16
        }
    }
}
