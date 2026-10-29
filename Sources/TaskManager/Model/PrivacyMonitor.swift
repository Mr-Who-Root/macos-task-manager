import AppKit
import Foundation
import Observation

/// The sensors behind macOS's privacy indicators in the menu bar.
enum Sensor: String, CaseIterable, Identifiable, Codable, Sendable {
    case camera = "cam", microphone = "mic", screen = "scr", location = "loc"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: return "Camera"
        case .microphone: return "Microphone"
        case .screen: return "Screen recording"
        case .location: return "Location"
        }
    }

    var symbol: String {
        switch self {
        case .camera: return "video.fill"
        case .microphone: return "mic.fill"
        case .screen: return "rectangle.inset.filled.on.rectangle"
        case .location: return "location.fill"
        }
    }
}

/// One stretch of an app using a sensor.
struct SensorSession: Identifiable, Hashable, Sendable {
    let sensor: Sensor
    let bundleID: String
    let start: Date
    var end: Date?

    var id: String { "\(sensor.rawValue):\(bundleID):\(start.timeIntervalSinceReferenceDate)" }
    var isActive: Bool { end == nil }
}

/// Which apps are using the camera, microphone, screen recording and location, now and over the
/// last 24 hours. It follows the same attributions Control Center logs for the menu bar indicators.
@Observable @MainActor
final class PrivacyMonitor {
    /// Sessions in the last 24 hours, newest first.
    private(set) var sessions: [SensorSession] = []
    /// False when the log couldn't be read.
    private(set) var isAvailable = true
    private(set) var isLoading = true

    @ObservationIgnored private var stream: Process?
    @ObservationIgnored private var buffer = Data()

    nonisolated static let predicate = #"subsystem == "com.apple.controlcenter" AND category == "sensor-indicators" AND eventMessage BEGINSWITH "Active activity attributions changed""#
    /// Gaps shorter than this join two sessions (some apps flick a sensor on and off).
    static let mergeGap: TimeInterval = 60

    var active: [SensorSession] { sessions.filter(\.isActive) }

    func active(_ sensor: Sensor) -> [SensorSession] { sessions.filter { $0.sensor == sensor && $0.isActive } }

    func start() {
        guard stream == nil else { return }
        Task.detached(priority: .utility) {
            let backfill = Shell.run("/usr/bin/log", ["show", "--last", "24h", "--style", "ndjson", "--predicate", Self.predicate])
            let events = Self.parseLines(backfill.output)
            await MainActor.run {
                self.isAvailable = backfill.succeeded
                for event in events { self.apply(event.sensors, at: event.time) }
                self.isLoading = false
                self.startStream()
            }
        }
    }

    func stop() {
        let process = stream
        stream = nil
        process?.terminate()
    }

    private func startStream() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["stream", "--style", "ndjson", "--predicate", Self.predicate]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // End of file: without this the handler keeps firing and spins a core.
                handle.readabilityHandler = nil
                return
            }
            Task { @MainActor in self?.receive(data) }
        }
        process.terminationHandler = { [weak self] _ in
            // If `log stream` exits on its own, start it again shortly.
            Task { @MainActor in
                guard let self, self.stream === process else { return }
                self.stream = nil
                try? await Task.sleep(for: .seconds(5))
                if self.stream == nil { self.startStream() }
            }
        }
        do {
            try process.run()
            stream = process
        } catch {
            isAvailable = false
        }
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        guard let newline = buffer.lastIndex(of: UInt8(ascii: "\n")) else { return }
        let complete = buffer[...newline]
        buffer = Data(buffer[buffer.index(after: newline)...])
        for event in Self.parseLines(String(decoding: complete, as: UTF8.self)) {
            apply(event.sensors, at: Date())
        }
    }

    /// Updates sessions from the full list of active attributions at a moment.
    func apply(_ attributions: [(Sensor, String)], at time: Date) {
        let now = Set(attributions.map { "\($0.0.rawValue):\($0.1)" })
        var updated = sessions
        for i in updated.indices where updated[i].isActive && !now.contains("\(updated[i].sensor.rawValue):\(updated[i].bundleID)") {
            updated[i].end = time
        }
        for (sensor, bundleID) in attributions where !updated.contains(where: { $0.isActive && $0.sensor == sensor && $0.bundleID == bundleID }) {
            // Reopen a session that ended moments ago rather than starting a new one.
            if let recent = updated.firstIndex(where: {
                $0.sensor == sensor && $0.bundleID == bundleID && $0.end.map { time.timeIntervalSince($0) < Self.mergeGap } == true
            }) {
                updated[recent].end = nil
            } else {
                updated.append(SensorSession(sensor: sensor, bundleID: bundleID, start: time, end: nil))
            }
        }
        let cutoff = time.addingTimeInterval(-24 * 3600)
        sessions = updated.filter { ($0.end ?? time) > cutoff }.sorted { $0.start > $1.start }
    }

    // MARK: Parsing

    struct Event {
        let time: Date
        let sensors: [(Sensor, String)]
    }

    // DateFormatter is safe to share for parsing on current macOS.
    nonisolated(unsafe) private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        return f
    }()

    /// Reads `log --style ndjson` output; lines that aren't attribution events are skipped.
    nonisolated static func parseLines(_ output: String) -> [Event] {
        output.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = object["eventMessage"] as? String,
                  let sensors = parseAttributions(message) else { return nil }
            let time = (object["timestamp"] as? String).flatMap { timestampFormatter.date(from: $0) } ?? Date()
            return Event(time: time, sensors: sensors)
        }
    }

    /// `Active activity attributions changed to ["scr:com.example.App", "mic:com.apple.FaceTime"]`.
    nonisolated static func parseAttributions(_ message: String) -> [(Sensor, String)]? {
        guard message.hasPrefix("Active activity attributions changed to"),
              let open = message.firstIndex(of: "["), let close = message.lastIndex(of: "]"), open < close else { return nil }
        let list = message[message.index(after: open)..<close]
        return list.split(separator: ",").compactMap { item in
            let entry = item.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            guard let colon = entry.firstIndex(of: ":"), let sensor = Sensor(rawValue: String(entry[..<colon])) else { return nil }
            let bundleID = String(entry[entry.index(after: colon)...])
            return bundleID.isEmpty ? nil : (sensor, bundleID)
        }
    }
}

/// App names and icons for bundle identifiers, cached.
@MainActor
enum AppLookup {
    private static var cache: [String: (name: String, path: String?)] = [:]

    /// macOS services that use the sensors but aren't apps.
    static let systemNames: [String: String] = [
        "com.apple.CoreSpeech": "Siri and Dictation",
        "com.apple.AssistantServices": "Siri",
        "com.apple.assistantd": "Siri",
        "com.apple.SiriNCService": "Siri",
        "com.apple.locationd": "Location Services",
        "com.apple.screencaptureui": "Screenshot",
        "com.apple.controlcenter": "Control Center",
    ]

    static func info(_ bundleID: String) -> (name: String, path: String?) {
        if let cached = cache[bundleID] { return cached }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        let name = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? systemNames[bundleID]
            ?? (bundleID.hasPrefix("com.apple.") ? String(bundleID.split(separator: ".").last ?? Substring(bundleID)) : bundleID)
        let info = (name, url?.path)
        cache[bundleID] = info
        return info
    }
}
