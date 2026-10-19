import Foundation

enum Shell {
    struct Result: Sendable {
        let status: Int32
        let output: String
        let error: String
        var succeeded: Bool { status == 0 }
    }

    /// Runs a program synchronously and captures its output. Call off the main thread.
    @discardableResult
    static func run(_ path: String, _ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return Result(status: -1, output: "", error: error.localizedDescription)
        }
        // Drain stderr concurrently so neither pipe can fill up and block the child.
        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errBox.data = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        return Result(
            status: process.terminationStatus,
            output: String(decoding: outData, as: UTF8.self),
            error: String(decoding: errBox.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Runs a shell command as root. macOS shows its own administrator password prompt.
    static func runAsAdmin(_ command: String) -> Result {
        run("/usr/bin/osascript", ["-e", "do shell script \(appleScriptString(command)) with administrator privileges"])
    }

    static func appleScript(_ source: String) -> Result {
        run("/usr/bin/osascript", ["-e", source])
    }

    static func wasCancelled(_ result: Result) -> Bool {
        result.error.contains("-128") || result.error.localizedCaseInsensitiveContains("cancel")
    }

    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }
}
