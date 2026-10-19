import AppKit

/// Backs the "Create new task" dialog.
enum TaskLauncher {
    /// Windows commands people type out of habit, mapped to their Mac equivalents.
    private static let aliases: [String: String] = [
        "notepad": "TextEdit", "calc": "Calculator", "cmd": "Terminal", "powershell": "Terminal", "pwsh": "Terminal",
        "explorer": "Finder", "mspaint": "Preview", "control": "System Settings", "msconfig": "System Settings",
        "taskmgr": "Task Manager", "regedit": "Terminal", "charmap": "Character Viewer", "snippingtool": "Screenshot",
        "eventvwr": "Console", "perfmon": "Activity Monitor", "devmgmt.msc": "System Information", "msinfo32": "System Information",
    ]

    private static var applicationDirectories: [String] {
        ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
         NSHomeDirectory() + "/Applications", "/System/Library/CoreServices", "/System/Library/CoreServices/Applications"]
    }

    /// Opens or runs `input`. Returns an error message to show in the dialog, or nil on success.
    @MainActor
    static func launch(_ input: String, asAdmin: Bool) async -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if asAdmin {
            let result = await Task.detached { Shell.runAsAdmin(text) }.value
            if result.succeeded || Shell.wasCancelled(result) { return nil }
            return result.error.isEmpty ? "The task couldn't be created." : result.error
        }

        let lowered = text.lowercased()
        if lowered == "taskmgr" || lowered == "task manager" {
            AppState.shared.bringToFront()
            return nil
        }

        let expanded = (text as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
            return nil
        }
        if let url = URL(string: text), let scheme = url.scheme, scheme.count > 1, text.contains(":") {
            NSWorkspace.shared.open(url)
            return nil
        }
        if lowered.hasPrefix("www."), let url = URL(string: "https://" + text) {
            NSWorkspace.shared.open(url)
            return nil
        }
        if let app = findApplication(aliases[lowered] ?? text) {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            return nil
        }

        // Fall back to running it as a shell command, if the program exists.
        let program = String(text.split(separator: " ").first ?? Substring(text))
        let found = await Task.detached { Shell.run("/bin/zsh", ["-lc", "command -v \(Shell.quote(program))"]).succeeded }.value
        guard found else {
            return "Task Manager cannot find '\(text)'. Make sure you typed the name correctly, and then try again."
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", text]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return error.localizedDescription
        }
        return nil
    }

    static func findApplication(_ name: String) -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) { return url }
        let base = name.lowercased().hasSuffix(".app") ? String(name.dropLast(4)) : name
        let target = base.lowercased() + ".app"
        for directory in applicationDirectories {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else { continue }
            if let match = entries.first(where: { $0.lowercased() == target }) {
                return URL(fileURLWithPath: directory).appendingPathComponent(match)
            }
        }
        return nil
    }
}
