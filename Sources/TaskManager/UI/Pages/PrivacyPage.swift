import SwiftUI

/// Which apps are using the camera, microphone, screen recording and location, now and over the last
/// 24 hours, and which are listening for network connections.
struct PrivacyPage: View {
    @Environment(Monitor.self) private var monitor
    @Environment(AppState.self) private var state

    var body: some View {
        let privacy = monitor.privacy
        let query = state.searchText.trimmingCharacters(in: .whitespaces)
        let active = privacy.active
        VStack(spacing: 0) {
            PageHeader(title: "Privacy") {
                HStack(spacing: 6) {
                    Circle().fill(active.isEmpty ? Fluent.efficiency : SensorStyle.color(active[0].sensor)).frame(width: 7, height: 7)
                    Text(active.isEmpty ? "Nothing in use" : "\(Set(active.map(\.sensor)).map(\.title).sorted().joined(separator: ", ")) in use")
                }
                .font(.system(size: 12))
                .foregroundStyle(Fluent.textSecondary)
                .padding(.trailing, 8)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("The apps behind the privacy indicators in the menu bar: who is using your camera, microphone, screen and location, now and earlier.")
                        .font(.system(size: 12))
                        .foregroundStyle(Fluent.textSecondary)
                    if !privacy.isAvailable {
                        Label("Task Manager couldn't read the privacy indicator log on this Mac.", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12))
                            .foregroundStyle(ChargeScale.low)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                        ForEach(Sensor.allCases) { sensor in
                            SensorCard(
                                sensor: sensor,
                                active: privacy.active(sensor),
                                last: privacy.sessions.first { $0.sensor == sensor && !$0.isActive }
                            )
                        }
                    }
                    history(privacy.sessions.filter { query.isEmpty || AppLookup.info($0.bundleID).name.localizedCaseInsensitiveContains(query) },
                            loading: privacy.isLoading)
                    listening(query: query)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: Sections

    private func history(_ sessions: [SensorSession], loading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PrivacySectionTitle(title: "Last 24 hours", detail: sessions.isEmpty ? "" : "\(sessions.count)")
            PrivacyCard {
                if sessions.isEmpty {
                    Text(loading ? "Reading the last 24 hours…" : "No app has used the camera, microphone, screen recording or location in the last 24 hours.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Fluent.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    ForEach(Array(sessions.prefix(60).enumerated()), id: \.element.id) { index, session in
                        if index > 0 { Rectangle().fill(Fluent.divider).frame(height: 1) }
                        SessionRow(session: session)
                    }
                }
            }
        }
    }

    private func listening(query: String) -> some View {
        let ports = monitor.listeningPorts.filter { port in
            query.isEmpty || name(for: port.pid).localizedCaseInsensitiveContains(query) || String(port.port).hasPrefix(query)
        }
        return VStack(alignment: .leading, spacing: 6) {
            PrivacySectionTitle(title: "Listening for connections", detail: ports.isEmpty ? "" : "\(ports.count)")
            PrivacyCard {
                HStack(spacing: 0) {
                    Text("App").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Port").frame(width: 70, alignment: .trailing)
                    Text("Who can connect").frame(width: 190, alignment: .leading).padding(.leading, 18)
                    Text("PID").frame(width: 60, alignment: .trailing)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Fluent.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                Rectangle().fill(Fluent.divider).frame(height: 1)
                if ports.isEmpty {
                    Text("None of your apps are listening for connections.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Fluent.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                ForEach(ports) { port in
                    PortRow(port: port, node: node(for: port.pid), name: name(for: port.pid))
                }
            }
            Text("Shows your own apps. System services run as other users, and macOS only lets an administrator inspect them.")
                .font(.system(size: 11.5))
                .foregroundStyle(Fluent.textTertiary)
        }
    }

    private func node(for pid: Int32) -> ProcNode? { monitor.nodes.first { $0.pids.contains(pid) } }

    private func name(for pid: Int32) -> String {
        if let node = node(for: pid) {
            let process = node.members.first { $0.pid == pid }
            return node.members.count > 1 && process?.name != node.name ? "\(node.name) (\(process?.name ?? ""))" : node.name
        }
        return monitor.process(pid)?.name ?? "PID \(pid)"
    }
}

enum SensorStyle {
    static func color(_ sensor: Sensor) -> Color {
        switch sensor {
        case .camera: return Fluent.efficiency
        case .microphone: return ChargeScale.low
        case .screen: return ResourceColor.memory
        case .location: return ResourceColor.cpu
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "under a minute" }
        let minutes = Int(seconds / 60)
        return minutes < 60 ? "\(minutes) min" : String(format: "%d h %02d min", minutes / 60, minutes % 60)
    }
}

// MARK: - Pieces

private struct SensorCard: View {
    let sensor: Sensor
    let active: [SensorSession]
    let last: SensorSession?

    var body: some View {
        let color = SensorStyle.color(sensor)
        let inUse = !active.isEmpty
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: sensor.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(inUse ? Color.white : color)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(inUse ? color : color.opacity(0.14)))
                Text(sensor.title).font(.system(size: 13)).foregroundStyle(Fluent.textPrimary)
                Spacer()
                if inUse {
                    Text("In use")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(color.opacity(0.15)))
                }
            }
            if inUse {
                ForEach(active) { session in
                    let info = AppLookup.info(session.bundleID)
                    HStack(spacing: 6) {
                        ProcessIcon(path: info.path).frame(width: 18, height: 18)
                        Text(info.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    }
                    Text("Since \(session.start.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Fluent.textSecondary)
                }
            } else {
                Text("Not in use").font(.system(size: 14, weight: .semibold)).foregroundStyle(Fluent.textSecondary)
                Text(last.map { "Last used by \(AppLookup.info($0.bundleID).name) at \(($0.end ?? $0.start).formatted(date: .omitted, time: .shortened))" }
                     ?? "Not used in the last 24 hours")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Fluent.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).fill(Fluent.card))
        .overlay(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).strokeBorder(inUse ? color.opacity(0.6) : Fluent.cardStroke))
    }
}

private struct SessionRow: View {
    let session: SensorSession
    @State private var hovering = false

    var body: some View {
        let info = AppLookup.info(session.bundleID)
        let end = session.end ?? Date()
        HStack(spacing: 10) {
            ProcessIcon(path: info.path).frame(width: 18, height: 18)
            Text(info.name).font(.system(size: 12.5)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Label(session.sensor.title, systemImage: session.sensor.symbol)
                .font(.system(size: 12))
                .foregroundStyle(SensorStyle.color(session.sensor))
                .frame(width: 170, alignment: .leading)
            Text(session.isActive
                 ? "Since \(session.start.formatted(date: .omitted, time: .shortened))"
                 : "\(session.start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Fluent.textSecondary)
                .frame(width: 150, alignment: .trailing)
            Text(SensorStyle.duration(end.timeIntervalSince(session.start)))
                .font(.system(size: 12))
                .foregroundStyle(Fluent.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 130, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(hovering ? Fluent.rowHover : .clear)
        .onHover { hovering = $0 }
        .help(session.bundleID)
    }
}

private struct PortRow: View {
    let port: ListeningPort
    let node: ProcNode?
    let name: String
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                ProcessIcon(path: node?.iconPath, symbol: node?.iconPath == nil ? "network" : nil).frame(width: 16, height: 16)
                Text(name).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(port.port)).monospacedDigit().frame(width: 70, alignment: .trailing)
            Label(port.localOnly ? "This Mac only" : "Other devices on the network",
                  systemImage: port.localOnly ? "lock" : "network")
                .foregroundStyle(port.localOnly ? Fluent.textSecondary : ChargeScale.low)
                .frame(width: 190, alignment: .leading)
                .padding(.leading, 18)
            Text(String(port.pid)).monospacedDigit().foregroundStyle(Fluent.textSecondary).frame(width: 60, alignment: .trailing)
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(hovering ? Fluent.rowHover : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            if let node {
                ProcessRowMenu(row: {
                    var row = ProcessRows.row(for: node, expanded: false)
                    row.isExpandable = false
                    return row
                }(), toggle: { _ in })
            }
        }
    }
}

private struct PrivacySectionTitle: View {
    let title: String
    var detail = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Fluent.textPrimary)
            Text(detail).font(.system(size: 12)).foregroundStyle(Fluent.textSecondary)
        }
    }
}

private struct PrivacyCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).fill(Fluent.card))
            .overlay(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).strokeBorder(Fluent.cardStroke))
            .clipShape(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous))
    }
}
