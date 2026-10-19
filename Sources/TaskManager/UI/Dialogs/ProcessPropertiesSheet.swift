import AppKit
import SwiftUI

struct ProcessPropertiesSheet: View {
    let pid: Int32
    @Environment(Monitor.self) private var monitor
    @Environment(\.dismiss) private var dismiss
    @State private var arguments: [String]?
    @State private var publisher = ""
    @State private var snapshot: ProcessSample?

    var body: some View {
        let process = monitor.process(pid) ?? snapshot
        VStack(alignment: .leading, spacing: 14) {
            if let process {
                header(process)
                Divider()
                KeyValueGrid(rows: rows(process), labelWidth: 120)
            } else {
                Text("This process has exited.")
                    .foregroundStyle(Fluent.textSecondary)
            }
            HStack(spacing: 8) {
                Button("Open file location") { ProcessActions.revealInFinder(process?.path) }
                    .buttonStyle(StandardButtonStyle())
                    .disabled(process?.path == nil)
                Button("Copy") {
                    if let process {
                        ProcessActions.copy(rows(process).map { "\($0.0)\t\($0.1)" }.joined(separator: "\n"))
                    }
                }
                .buttonStyle(StandardButtonStyle())
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(AccentButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 600)
        .task {
            snapshot = monitor.process(pid)
            arguments = Sysctl.arguments(of: pid)
            if let path = snapshot.flatMap({ BundlePaths.innermostApp($0.path) ?? $0.path }) {
                publisher = await Task.detached { CodeSigning.publisher(for: path) }.value
            }
        }
    }

    private func header(_ process: ProcessSample) -> some View {
        HStack(spacing: 14) {
            ProcessIcon(path: process.iconPath).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(process))
                    .font(.system(size: 17, weight: .semibold))
                Text(publisher.isEmpty ? "Unknown publisher" : publisher)
                    .font(.system(size: 12))
                    .foregroundStyle(Fluent.textSecondary)
            }
        }
    }

    private func displayName(_ process: ProcessSample) -> String {
        NSRunningApplication(processIdentifier: process.pid)?.localizedName ?? process.name
    }

    private func rows(_ process: ProcessSample) -> [(String, String)] {
        let parent = monitor.process(process.ppid).map { "\(process.ppid) (\($0.name))" } ?? String(process.ppid)
        var rows: [(String, String)] = [
            ("Name", displayName(process)),
            ("Process ID", String(process.pid)),
            ("Parent process", parent),
            ("User", process.user),
            ("Status", process.detailStatus + (process.efficiencyMode ? " · Efficiency mode" : "")),
            ("Architecture", process.architecture),
            ("Priority", "\(process.priorityName) (nice \(process.nice))"),
            ("Started", process.startTime.formatted(date: .abbreviated, time: .standard)),
            ("CPU time", Fmt.cpuTime(process.cpuTime)),
            ("Memory", Fmt.megabytes(process.memory)),
            ("Threads", process.threads > 0 ? String(process.threads) : "—"),
            ("Path", process.path ?? "—"),
            ("Command line", arguments.map { $0.joined(separator: " ") } ?? "Not available for processes owned by other users"),
        ]
        if let bundlePath = BundlePaths.innermostApp(process.path), let bundle = Bundle(path: bundlePath) {
            rows.append(("Bundle identifier", bundle.bundleIdentifier ?? "—"))
            if let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                rows.append(("Version", version))
            }
        }
        return rows
    }
}
