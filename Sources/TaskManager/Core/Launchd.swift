import Foundation

struct ServiceEntry: Identifiable, Hashable, Sendable {
    enum Domain: String, Sendable { case user = "User", system = "System" }

    let label: String
    let domain: Domain
    let pid: Int32?
    let lastExit: String
    let program: String
    let plistPath: String?

    var id: String { domain.rawValue + "/" + label }
    var isRunning: Bool { pid != nil }
    var status: String { isRunning ? "Running" : "Stopped" }
    var pidSortKey: Int32 { pid ?? -1 }
    var pidText: String { pid.map(String.init) ?? "" }

    var target: String {
        domain == .system ? "system/\(label)" : "gui/\(getuid())/\(label)"
    }
}

struct StartupItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case loginItem = "Login item"
        case agent = "Launch agent"
        case daemon = "Launch daemon"
    }

    let id: String
    let name: String
    let kind: Kind
    let label: String?
    let plistPath: String?
    let programPath: String?
    let publisher: String
    let enabled: Bool
    let trigger: String
    let iconPath: String?

    var status: String { enabled ? "Enabled" : "Disabled" }
    var location: String { plistPath ?? programPath ?? "" }
}

enum Launchd {
    struct PlistInfo: Sendable {
        let path: String
        let program: String
        let runAtLoad: Bool
        let keepAlive: Bool
        let scheduled: Bool
        let disabledKey: Bool
    }

    static var userAgentsDirectory: String { NSHomeDirectory() + "/Library/LaunchAgents" }

    static func readPlist(_ path: String) -> (label: String, info: PlistInfo)? {
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = plist["Label"] as? String else { return nil }
        let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first ?? (plist["BundleProgram"] as? String) ?? ""
        let keepAlive: Bool
        if let flag = plist["KeepAlive"] as? Bool { keepAlive = flag } else { keepAlive = plist["KeepAlive"] is [String: Any] }
        return (label, PlistInfo(
            path: path,
            program: program,
            runAtLoad: plist["RunAtLoad"] as? Bool ?? false,
            keepAlive: keepAlive,
            scheduled: plist["StartInterval"] != nil || plist["StartCalendarInterval"] != nil,
            disabledKey: plist["Disabled"] as? Bool ?? false
        ))
    }

    /// Label → plist for every launchd job definition on disk.
    static func plistIndex() -> [String: PlistInfo] {
        let directories = [
            "/System/Library/LaunchAgents", "/System/Library/LaunchDaemons",
            "/Library/LaunchAgents", "/Library/LaunchDaemons", userAgentsDirectory,
        ]
        var index: [String: PlistInfo] = [:]
        for directory in directories {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory) else { continue }
            for file in files where file.hasSuffix(".plist") {
                if let entry = readPlist("\(directory)/\(file)") { index[entry.label] = entry.info }
            }
        }
        return index
    }

    // MARK: Services

    static func services() -> [ServiceEntry] {
        let index = plistIndex()
        var result: [ServiceEntry] = []

        // User domain: "PID\tStatus\tLabel"
        for line in Shell.run("/bin/launchctl", ["list"]).output.split(separator: "\n").dropFirst() {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { continue }
            let label = String(fields[2])
            result.append(ServiceEntry(
                label: label, domain: .user, pid: Int32(fields[0]), lastExit: String(fields[1]),
                program: index[label]?.program ?? "", plistPath: index[label]?.path
            ))
        }

        // System domain: the "services = { … }" block of `launchctl print system`.
        var inServices = false
        for line in Shell.run("/bin/launchctl", ["print", "system"]).output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inServices {
                if trimmed == "services = {" { inServices = true }
                continue
            }
            if trimmed == "}" { break }
            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 3 else { continue }
            let label = String(parts[2])
            let pid = Int32(parts[0]).flatMap { $0 > 0 ? $0 : nil }
            result.append(ServiceEntry(
                label: label, domain: .system, pid: pid, lastExit: String(parts[1]),
                program: index[label]?.program ?? "", plistPath: index[label]?.path
            ))
        }
        return result
    }

    enum ServiceAction { case start, stop, restart }

    static func perform(_ action: ServiceAction, on service: ServiceEntry) -> Shell.Result {
        let arguments: [String]
        switch action {
        case .start: arguments = ["kickstart", service.target]
        case .stop: arguments = ["kill", "SIGTERM", service.target]
        case .restart: arguments = ["kickstart", "-k", service.target]
        }
        if service.domain == .system {
            return Shell.runAsAdmin((["/bin/launchctl"] + arguments).map(Shell.quote).joined(separator: " "))
        }
        return Shell.run("/bin/launchctl", arguments)
    }

    // MARK: Startup items

    private static func disabledOverrides(_ domain: String) -> [String: Bool] {
        var result: [String: Bool] = [:]
        for line in Shell.run("/bin/launchctl", ["print-disabled", domain]).output.split(separator: "\n") {
            // "\t\"com.example.agent\" => disabled"
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let label = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            result[label] = parts[1].trimmingCharacters(in: .whitespaces).hasPrefix("disabled")
        }
        return result
    }

    /// Third-party launch agents and daemons that are installed on disk.
    static func launchdStartupItems() -> [StartupItem] {
        let userOverrides = disabledOverrides("gui/\(getuid())")
        let systemOverrides = disabledOverrides("system")
        let sources: [(String, StartupItem.Kind)] = [
            (userAgentsDirectory, .agent), ("/Library/LaunchAgents", .agent), ("/Library/LaunchDaemons", .daemon),
        ]
        var items: [StartupItem] = []
        for (directory, kind) in sources {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory) else { continue }
            for file in files.sorted() where file.hasSuffix(".plist") {
                guard let (label, info) = readPlist("\(directory)/\(file)") else { continue }
                let overrides = kind == .daemon ? systemOverrides : userOverrides
                let enabled = !(overrides[label] ?? info.disabledKey)
                let program = info.program.isEmpty ? nil : info.program
                let bundle = BundlePaths.outermostApp(program)
                let executable = program.map { ($0 as NSString).lastPathComponent }
                let interpreters: Set<String> = ["sh", "bash", "zsh", "env", "python", "python3", "perl", "ruby", "node", "osascript", "open"]
                let name = bundle.map(BundlePaths.displayName) ?? executable.flatMap { interpreters.contains($0) ? nil : $0 } ?? label
                let trigger: String
                if info.keepAlive { trigger = "Always running" }
                else if info.runAtLoad { trigger = kind == .daemon ? "At startup" : "At login" }
                else if info.scheduled { trigger = "Scheduled" }
                else { trigger = "On demand" }
                items.append(StartupItem(
                    id: "\(kind.rawValue):\(label)",
                    name: name,
                    kind: kind,
                    label: label,
                    plistPath: info.path,
                    programPath: program,
                    publisher: (bundle ?? program).map(CodeSigning.publisher(for:)) ?? "",
                    enabled: enabled,
                    trigger: trigger,
                    iconPath: bundle ?? program
                ))
            }
        }
        return items
    }

    static let disabledLoginItemsKey = "disabledLoginItems"

    /// Items from System Settings › General › Login Items › "Open at Login", via System Events.
    /// Returns nil if the user hasn't allowed Task Manager to control System Events.
    static func loginItems(disabled: [[String]]) -> [StartupItem]? {
        let script = """
        set output to ""
        tell application "System Events"
            repeat with anItem in login items
                set output to output & (name of anItem) & tab & (path of anItem) & linefeed
            end repeat
        end tell
        return output
        """
        let result = Shell.appleScript(script)
        guard result.succeeded else { return nil }
        var items: [StartupItem] = []
        var seen: Set<String> = []
        func make(name: String, path: String, enabled: Bool) -> StartupItem {
            // AppleScript reports "missing value" when the item's file can't be resolved.
            let resolved = path.isEmpty || path == "missing value" ? TaskLauncher.findApplication(name)?.path : path
            return StartupItem(
                id: "login:\(name):\(resolved ?? "")", name: name, kind: .loginItem, label: nil, plistPath: nil, programPath: resolved,
                publisher: resolved.map(CodeSigning.publisher(for:)) ?? "", enabled: enabled, trigger: "At login", iconPath: resolved
            )
        }
        for line in result.output.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 2, !seen.contains(fields[0]) else { continue }
            seen.insert(fields[0])
            items.append(make(name: fields[0], path: fields[1], enabled: true))
        }
        for entry in disabled where entry.count == 2 && !seen.contains(entry[0]) {
            items.append(make(name: entry[0], path: entry[1], enabled: false))
        }
        return items
    }

    /// Enables or disables a startup item. Returns an error message on failure.
    static func setEnabled(_ enabled: Bool, item: StartupItem) -> String? {
        switch item.kind {
        case .loginItem:
            let script: String
            if enabled {
                guard let path = item.programPath else { return "Task Manager can't find “\(item.name)” to add it back." }
                script = "tell application \"System Events\" to make login item at end with properties {path:\(Shell.appleScriptString(path)), hidden:false}"
            } else {
                script = "tell application \"System Events\" to delete (every login item whose name is \(Shell.appleScriptString(item.name)))"
            }
            let result = Shell.appleScript(script)
            guard result.succeeded else { return result.error }
            var disabled = UserDefaults.standard.array(forKey: disabledLoginItemsKey) as? [[String]] ?? []
            disabled.removeAll { $0.count == 2 && $0[0] == item.name }
            if !enabled { disabled.append([item.name, item.programPath ?? ""]) }
            UserDefaults.standard.set(disabled, forKey: disabledLoginItemsKey)
            return nil
        case .agent:
            guard let label = item.label else { return nil }
            let domain = "gui/\(getuid())"
            let result = Shell.run("/bin/launchctl", [enabled ? "enable" : "disable", "\(domain)/\(label)"])
            guard result.succeeded else { return result.error.isEmpty ? "launchctl failed." : result.error }
            if enabled, let plist = item.plistPath {
                Shell.run("/bin/launchctl", ["bootstrap", domain, plist])
            } else if !enabled {
                Shell.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"])
            }
            return nil
        case .daemon:
            guard let label = item.label else { return nil }
            var command = "/bin/launchctl \(enabled ? "enable" : "disable") \(Shell.quote("system/\(label)"))"
            if enabled, let plist = item.plistPath {
                command += "; /bin/launchctl bootstrap system \(Shell.quote(plist)) 2>/dev/null; true"
            } else if !enabled {
                command += "; /bin/launchctl bootout \(Shell.quote("system/\(label)")) 2>/dev/null; true"
            }
            let result = Shell.runAsAdmin(command)
            if Shell.wasCancelled(result) { return "" }
            return result.succeeded ? nil : result.error
        }
    }
}
