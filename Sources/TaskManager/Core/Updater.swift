import AppKit
import CryptoKit
import Foundation
import Observation

struct ReleaseInfo: Equatable, Sendable {
    let version: String
    let title: String
    let notes: String
    let pageURL: URL
    let archiveURL: URL
    let checksumURL: URL?
    let publishedAt: Date?
    let size: Int
}

struct UpdateError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Checks GitHub Releases for a newer version and installs it in place.
@Observable @MainActor
final class Updater {
    static let shared = Updater()
    nonisolated static let archiveName = "TaskManager.zip"

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case downloading(ReleaseInfo, Double)
        case installing(ReleaseInfo)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var lastChecked: Date?

    let repository: String
    let currentVersion: String

    @ObservationIgnored private var timer: Timer?

    /// The release to offer, if one is waiting to be installed.
    var pendingRelease: ReleaseInfo? {
        switch phase {
        case .available(let release), .downloading(let release, _), .installing(let release): return release
        default: return nil
        }
    }

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    /// Updates replace the running bundle, which needs a real .app (not `swift run`).
    var canInstallInPlace: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    var releasesPage: URL { URL(string: "https://github.com/\(repository)/releases")! }

    private init() {
        repository = Bundle.main.object(forInfoDictionaryKey: "TMUpdateRepository") as? String ?? "Mr-Who-Root/macos-task-manager"
        currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        lastChecked = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date
    }

    // MARK: Checking

    /// Checks on launch and then every few hours, at most once a day.
    func startAutomaticChecks() {
        checkIfDue()
        timer?.invalidate()
        let timer = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func checkIfDue() {
        guard AppSettings.shared.autoCheckUpdates, !isBusy, pendingRelease == nil else { return }
        if let lastChecked, Date().timeIntervalSince(lastChecked) < 20 * 3600 { return }
        Task { await checkForUpdates(userInitiated: false) }
    }

    func checkForUpdates(userInitiated: Bool) async {
        guard !isBusy else { return }
        phase = .checking
        do {
            let release = try await Self.fetchLatestRelease(repository: repository)
            lastChecked = Date()
            UserDefaults.standard.set(lastChecked, forKey: "lastUpdateCheck")
            phase = Self.isVersion(release.version, newerThan: currentVersion) ? .available(release) : .upToDate
        } catch {
            // Background checks fail quietly; there's nothing the user needs to do.
            phase = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    // MARK: Installing

    func downloadAndInstall() async {
        guard let release = pendingRelease, !isBusy else { return }
        guard canInstallInPlace else {
            NSWorkspace.shared.open(release.pageURL)
            return
        }
        phase = .downloading(release, 0)
        do {
            let archive = try await Self.download(release.archiveURL) { fraction in
                Task { @MainActor in
                    if case .downloading = Updater.shared.phase { Updater.shared.phase = .downloading(release, fraction) }
                }
            }
            if let checksumURL = release.checksumURL {
                try await Self.verifyChecksum(of: archive, against: checksumURL)
            }
            phase = .installing(release)
            let bundleID = Bundle.main.bundleIdentifier ?? "dev.taskmanager.mac"
            let newApp = try await Task.detached {
                try Self.extractApp(from: archive, bundleIdentifier: bundleID, version: release.version)
            }.value
            try Self.replaceAndRelaunch(current: Bundle.main.bundleURL, with: newApp)
            Monitor.shared.appHistory.save()
            NSApp.terminate(nil)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: Steps (nonisolated so they can run off the main actor)

    nonisolated static func fetchLatestRelease(repository: String) async throws -> ReleaseInfo {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TaskManager-macOS", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError(message: "GitHub didn't respond.") }
        if http.statusCode == 404 { throw UpdateError(message: "No releases have been published yet.") }
        if http.statusCode == 403 { throw UpdateError(message: "GitHub's rate limit was reached. Try again in a little while.") }
        guard http.statusCode == 200 else { throw UpdateError(message: "GitHub returned an error (\(http.statusCode)).") }

        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
                let size: Int
            }
            let tag_name: String
            let name: String?
            let body: String?
            let html_url: URL
            let published_at: Date?
            let assets: [Asset]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(Payload.self, from: data)
        guard let archive = payload.assets.first(where: { $0.name == archiveName }) else {
            throw UpdateError(message: "The latest release doesn't include \(archiveName).")
        }
        let version = payload.tag_name.hasPrefix("v") ? String(payload.tag_name.dropFirst()) : payload.tag_name
        return ReleaseInfo(
            version: version,
            title: payload.name ?? "Task Manager \(version)",
            notes: payload.body ?? "",
            pageURL: payload.html_url,
            archiveURL: archive.browser_download_url,
            checksumURL: payload.assets.first { $0.name == archiveName + ".sha256" }?.browser_download_url,
            publishedAt: payload.published_at,
            size: archive.size
        )
    }

    /// Compares dotted versions numerically: 1.10.0 is newer than 1.9.2.
    nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        func parts(_ v: String) -> [Int] { v.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    nonisolated static func download(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let delegate = DownloadDelegate(progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    nonisolated static func verifyChecksum(of file: URL, against url: URL) async throws {
        let (data, _) = try await URLSession.shared.data(from: url)
        let expected = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? ""
        let digest = SHA256.hash(data: try Data(contentsOf: file, options: .mappedIfSafe))
        let actual = digest.map { String(format: "%02x", $0) }.joined()
        guard !expected.isEmpty, expected == actual else {
            throw UpdateError(message: "The download is damaged (its checksum doesn't match). Try again.")
        }
    }

    /// Unzips the archive and checks it really is the expected Task Manager build.
    nonisolated static func extractApp(from archive: URL, bundleIdentifier: String, version: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TaskManager-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: archive) }
        guard Shell.run("/usr/bin/ditto", ["-x", "-k", archive.path, directory.path]).succeeded else {
            throw UpdateError(message: "The update couldn't be unpacked.")
        }
        guard let app = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }),
            let bundle = Bundle(url: app) else {
            throw UpdateError(message: "The update doesn't contain an app.")
        }
        guard bundle.bundleIdentifier == bundleIdentifier else {
            throw UpdateError(message: "The downloaded app isn't Task Manager.")
        }
        guard (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) == version else {
            throw UpdateError(message: "The downloaded app's version doesn't match the release.")
        }
        guard Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]).succeeded else {
            throw UpdateError(message: "The downloaded app's code signature is invalid.")
        }
        Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        return app
    }

    /// Starts a small shell helper that waits for Task Manager to quit, swaps the
    /// bundles (restoring the old one if anything fails) and opens the new version.
    static func replaceAndRelaunch(current: URL, with newApp: URL) throws {
        let folder = current.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: folder.path),
              FileManager.default.isWritableFile(atPath: current.path) else {
            throw UpdateError(message: "Task Manager can't replace itself in “\(folder.path)”. Download the update from the website instead.")
        }
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        backup="$3.previous-$$"
        if mv "$3" "$backup"; then
          if mv "$2" "$3"; then rm -rf "$backup"; else mv "$backup" "$3"; fi
        fi
        open "$3"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "taskmanager-updater", String(getpid()), newApp.path, current.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let progress: @Sendable (Double) -> Void
        var continuation: CheckedContinuation<URL, Error>?

        init(progress: @escaping @Sendable (Double) -> Void) {
            self.progress = progress
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            if totalBytesExpectedToWrite > 0 {
                progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
            }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
                finish(.failure(UpdateError(message: "The download failed (\(http.statusCode)).")))
                return
            }
            // The file at `location` is deleted when this method returns, so move it now.
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("TaskManager-\(UUID().uuidString).zip")
            do {
                try FileManager.default.moveItem(at: location, to: destination)
                finish(.success(destination))
            } catch {
                finish(.failure(error))
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error { finish(.failure(error)) }
        }

        private func finish(_ result: Result<URL, Error>) {
            continuation?.resume(with: result)
            continuation = nil
        }
    }
}
