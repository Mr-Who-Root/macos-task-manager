import AppKit
import Darwin

/// What a row on the Processes / Users / Details tabs acts on.
struct RowTarget: Hashable {
    var pids: [Int32]
    let mainPID: Int32
    let isApp: Bool
    let name: String
    let path: String?
    let kind: ProcKind
    let uid: UInt32
    let efficiency: Bool
    let suspended: Bool

    var ownedByUser: Bool { uid == getuid() }

    static let finderPath = "/System/Library/CoreServices/Finder.app"

    /// Finder is never ended, only restarted, like Windows Explorer in Windows Task Manager.
    var isFinder: Bool { BundlePaths.outermostApp(path) == Self.finderPath }

    init(node: ProcNode) {
        pids = node.pids
        mainPID = node.mainPID
        isApp = node.isApp
        name = node.name
        path = node.path
        kind = node.kind
        uid = node.uid
        efficiency = node.efficiency == .on
        suspended = node.isSuspended
    }

    init(process: ProcessSample, kind: ProcKind, isApp: Bool = false) {
        pids = [process.pid]
        mainPID = process.pid
        self.isApp = isApp
        name = process.name
        path = process.path
        self.kind = kind
        uid = process.uid
        efficiency = process.efficiencyMode
        suspended = process.isSuspended
    }
}

@MainActor
enum ProcessActions {
    private static let essentialPIDs: Set<Int32> = [0, 1]

    /// Ends a task, asking first when it belongs to macOS or another user.
    static func requestEndTask(_ target: RowTarget, force: Bool = false) {
        guard !target.isFinder else { return }
        if target.pids.contains(where: essentialPIDs.contains) {
            AppState.shared.alert = AppAlert(
                title: "Task Manager can't end “\(target.name)”",
                message: "This process is part of the macOS kernel. Ending it would shut down your Mac immediately."
            )
            return
        }
        if target.kind == .system || !target.ownedByUser {
            AppState.shared.alert = AppAlert(
                title: "Do you want to end the system process “\(target.name)”?",
                message: "Ending this process may make macOS unstable or cause unsaved data to be lost. macOS may restart it automatically.",
                action: .init(title: force ? "Force end process" : "End process", role: .destructive) {
                    endTask(target, force: force)
                }
            )
            return
        }
        endTask(target, force: force)
    }

    static func endTask(_ target: RowTarget, force: Bool) {
        guard !target.isFinder else { return }
        if target.pids.contains(getpid()) {
            NSApp.terminate(nil)
            return
        }
        var denied: [Int32] = []
        if target.isApp, let app = NSRunningApplication(processIdentifier: target.mainPID) {
            _ = force ? app.forceTerminate() : app.terminate()
            if force { denied = send(SIGKILL, to: target.pids.filter { $0 != target.mainPID }) }
        } else {
            denied = send(force ? SIGKILL : SIGTERM, to: target.pids)
        }
        if !denied.isEmpty {
            AppState.shared.alert = AppAlert(
                title: "Access denied",
                message: "“\(target.name)” is owned by another user. You can end it as an administrator.",
                action: .init(title: "End as administrator", role: .destructive) {
                    runAsAdmin("/bin/kill -\(force ? 9 : 15) " + denied.map(String.init).joined(separator: " "))
                }
            )
        }
        Monitor.shared.refreshSoon()
    }

    /// Quits Finder and lets macOS relaunch it (relaunching it ourselves if macOS doesn't).
    static func restartFinder() {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder") {
            kill(app.processIdentifier, SIGTERM)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").isEmpty {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: RowTarget.finderPath),
                                                   configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            }
            Monitor.shared.refreshSoon()
        }
    }

    /// Turns efficiency mode on or off, asking first before turning it on (like Windows).
    static func requestEfficiency(_ target: RowTarget, enabled: Bool) {
        guard enabled, AppSettings.shared.confirmEfficiencyMode else {
            setEfficiency(target, enabled: enabled)
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Turn on Efficiency mode for “\(target.name)”?"
        alert.informativeText = """
        Efficiency mode lowers its CPU priority, moves it to the efficiency cores and throttles its disk and network use to save power.

        Apps you're actively using, such as web browsers, video calls, games and music, can stop feeling smooth. It works best for background work like syncing, indexing or long builds.

        To turn it off, select it and click Efficiency mode again, or quit and reopen the app. A green leaf in the Status column shows what's in efficiency mode.
        """
        alert.addButton(withTitle: "Turn on Efficiency mode")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            if alert.suppressionButton?.state == .on && response == .alertFirstButtonReturn {
                AppSettings.shared.confirmEfficiencyMode = false
            }
            if response == .alertFirstButtonReturn { setEfficiency(target, enabled: true) }
        }
        if let window = AppState.shared.window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    /// Efficiency mode = Darwin background priority (lower CPU and I/O priority), like EcoQoS on Windows.
    static func setEfficiency(_ target: RowTarget, enabled: Bool) {
        var denied: [Int32] = []
        var changed: [Int32] = []
        for pid in target.pids {
            if setpriority(PRIO_DARWIN_PROCESS, id_t(pid), enabled ? PRIO_DARWIN_BG : 0) == 0 {
                changed.append(pid)
            } else if errno == EPERM || errno == EACCES {
                denied.append(pid)
            }
        }
        EfficiencyStore.shared.setEnabled(enabled, pids: changed)
        if !denied.isEmpty {
            AppState.shared.alert = AppAlert(
                title: "Efficiency mode needs administrator rights",
                message: "“\(target.name)” is owned by another user.",
                action: .init(title: "Continue as administrator") {
                    let flag = enabled ? "-b" : "-B"
                    runAsAdmin(denied.map { "/usr/sbin/taskpolicy \(flag) -p \($0)" }.joined(separator: "; ")) {
                        EfficiencyStore.shared.setEnabled(enabled, pids: denied)
                    }
                }
            )
        }
        Monitor.shared.refreshSoon()
    }

    static func setSuspended(_ target: RowTarget, suspended: Bool) {
        let pids = target.pids.filter { $0 != getpid() && !essentialPIDs.contains($0) }
        let denied = send(suspended ? SIGSTOP : SIGCONT, to: pids)
        if !denied.isEmpty {
            AppState.shared.alert = AppAlert(title: "Access denied", message: "“\(target.name)” is owned by another user and can't be \(suspended ? "suspended" : "resumed").")
        }
        Monitor.shared.refreshSoon()
    }

    static func setPriority(pid: Int32, name: String, nice: Int32) {
        if setpriority(PRIO_PROCESS, id_t(pid), nice) != 0 {
            AppState.shared.alert = AppAlert(
                title: "Changing priority needs administrator rights",
                message: "Raising the priority of a process, or changing one owned by another user, requires an administrator.",
                action: .init(title: "Continue as administrator") {
                    runAsAdmin("/usr/bin/renice -n \(nice) -p \(pid)")
                }
            )
        }
        Monitor.shared.refreshSoon()
    }

    static func revealInFinder(_ path: String?) {
        guard let path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func searchOnline(_ name: String) {
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: "\(name) macOS process")]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Returns the PIDs that refused the signal for lack of permission.
    private static func send(_ signal: Int32, to pids: [Int32]) -> [Int32] {
        pids.filter { kill($0, signal) != 0 && errno == EPERM }
    }

    private static func runAsAdmin(_ command: String, onSuccess: (@MainActor () -> Void)? = nil) {
        Task.detached {
            let result = Shell.runAsAdmin(command)
            await MainActor.run {
                if result.succeeded {
                    onSuccess?()
                } else if !Shell.wasCancelled(result) {
                    AppState.shared.alert = AppAlert(title: "The operation couldn't be completed", message: result.error)
                }
                Monitor.shared.refreshSoon()
            }
        }
    }
}
