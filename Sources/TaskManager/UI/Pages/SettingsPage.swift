import SwiftUI

struct SettingsPage: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 0) {
            PageHeader(title: "Settings") { EmptyView() }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    sectionTitle("Design").padding(.top, -16)
                    DesignPicker()

                    sectionTitle("General")
                    SettingCard(systemImage: "house", title: "Default start page", subtitle: "Choose the page Task Manager opens on") {
                        Picker("", selection: $settings.defaultPage) {
                            ForEach(Page.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }
                    SettingCard(systemImage: "speedometer", title: "Real time update speed", subtitle: "How often graphs and figures refresh") {
                        Picker("", selection: $settings.updateSpeed) {
                            ForEach(UpdateSpeed.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }
                    SettingCard(systemImage: "circle.lefthalf.filled", title: "App theme",
                                subtitle: Fluent.design.isAlwaysDark ? "The \(Fluent.design.title) design is always dark" : "Light, dark, or follow macOS") {
                        Picker("", selection: $settings.theme) {
                            ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                        .disabled(Fluent.design.isAlwaysDark)
                    }

                    sectionTitle("Window management")
                    SettingCard(systemImage: "macwindow.on.rectangle", title: "Always on top", subtitle: "Keep Task Manager above other windows") {
                        Toggle("", isOn: $settings.alwaysOnTop).toggleStyle(.switch).labelsHidden().tint(Fluent.accent)
                    }
                    SettingCard(systemImage: "keyboard", title: "Open with Control-Shift-Escape",
                                subtitle: "The Windows shortcut brings Task Manager to the front from any app") {
                        Toggle("", isOn: $settings.globalHotKey).toggleStyle(.switch).labelsHidden().tint(Fluent.accent)
                    }

                    sectionTitle("Menu bar")
                    MenuBarItemsCard()
                    SettingCard(systemImage: "textformat.size", title: "Menu bar style", subtitle: "How each item looks in the menu bar") {
                        Picker("", selection: $settings.menuBarStyle) {
                            ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }
                    SettingCard(systemImage: "thermometer.medium", title: "Temperature unit", subtitle: "Used on the Temperatures page, menu bar and widgets") {
                        Picker("", selection: $settings.useFahrenheit) {
                            Text("Celsius (°C)").tag(false)
                            Text("Fahrenheit (°F)").tag(true)
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }

                    sectionTitle("Other options")
                    SettingCard(systemImage: "leaf", title: "Ask before turning on efficiency mode",
                                subtitle: "Show a confirmation explaining what efficiency mode does") {
                        Toggle("", isOn: $settings.confirmEfficiencyMode).toggleStyle(.switch).labelsHidden().tint(Fluent.accent)
                    }
                    SettingCard(systemImage: "rectangle.3.group", title: "Group processes by type", subtitle: "Split the Processes page into apps, background and macOS processes") {
                        Toggle("", isOn: $settings.groupByType).toggleStyle(.switch).labelsHidden().tint(Fluent.accent)
                    }
                    SettingCard(systemImage: "clock.arrow.circlepath", title: "Show history for all processes", subtitle: "Include background and macOS processes on the App history page") {
                        Toggle("", isOn: $settings.historyAllProcesses).toggleStyle(.switch).labelsHidden().tint(Fluent.accent)
                    }
                    SettingCard(systemImage: "person.text.rectangle", title: "Show full account name", subtitle: "Show the full name next to each account on the Users page") {
                        Toggle("", isOn: $settings.showFullAccountName).toggleStyle(.switch).labelsHidden().tint(Fluent.accent)
                    }

                    sectionTitle("Updates")
                    UpdatesSection()

                    sectionTitle("About")
                    SettingCard(systemImage: "info.circle", title: "Task Manager for macOS",
                                subtitle: "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0") · \(HardwareInfo.shared.cpuName) · \(HardwareInfo.shared.osVersion)") {
                        EmptyView()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
                .frame(maxWidth: 920, alignment: .leading)
            }
            .defaultScrollAnchor(DebugHooks.scrollAnchor)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Fluent.textPrimary)
            .padding(.top, 22)
            .padding(.bottom, 6)
    }
}

/// Online updates from GitHub Releases, styled like Windows Update.
private struct UpdatesSection: View {
    @Environment(AppSettings.self) private var settings
    private var updater: Updater { Updater.shared }

    var body: some View {
        @Bindable var settings = settings
        SettingCard(systemImage: icon, title: title, subtitle: subtitle) {
            controls
        }
        if let release = updater.pendingRelease, !release.notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("What's new in \(release.version)")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if let date = release.publishedAt {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 11.5))
                            .foregroundStyle(Fluent.textSecondary)
                    }
                }
                Text(Self.plainNotes(release.notes))
                    .font(.system(size: 12))
                    .foregroundStyle(Fluent.textSecondary)
                    .lineLimit(12)
                    .textSelection(.enabled)
                Button("View full release notes") { NSWorkspace.shared.open(release.pageURL) }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Fluent.card))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Fluent.cardStroke))
        }
        SettingCard(systemImage: "clock.arrow.2.circlepath", title: "Check for updates automatically",
                    subtitle: "Look for a new version on GitHub once a day") {
            Toggle("", isOn: $settings.autoCheckUpdates).toggleStyle(.switch).labelsHidden().tint(Fluent.accent)
        }
    }

    private var icon: String {
        switch updater.phase {
        case .available, .downloading, .installing: return "arrow.down.circle"
        case .failed: return "exclamationmark.triangle"
        case .upToDate: return "checkmark.circle"
        default: return "arrow.triangle.2.circlepath"
        }
    }

    private var title: String {
        switch updater.phase {
        case .checking: return "Checking for updates…"
        case .upToDate: return "You're up to date"
        case .available(let release): return "Task Manager \(release.version) is available"
        case .downloading(let release, _): return "Downloading Task Manager \(release.version)…"
        case .installing: return "Installing update…"
        case .failed: return "Couldn't check for updates"
        case .idle: return "Task Manager updates"
        }
    }

    private var subtitle: String {
        let installed = "Installed version \(updater.currentVersion)"
        switch updater.phase {
        case .available(let release):
            return installed + " · Download size \(Fmt.bytes(Double(release.size)))"
                + (updater.canInstallInPlace ? "" : " · Run the bundled app to install in place")
        case .downloading(_, let fraction): return "\(Int(fraction * 100))% downloaded"
        case .installing: return "Task Manager will restart when the update is installed"
        case .failed(let message): return message
        default:
            guard let checked = updater.lastChecked else { return installed }
            return installed + " · Last checked " + checked.formatted(.relative(presentation: .named))
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch updater.phase {
        case .checking, .installing:
            ProgressView().controlSize(.small)
        case .downloading(_, let fraction):
            ProgressView(value: fraction).frame(width: 140).tint(Fluent.accent)
        case .available:
            HStack(spacing: 8) {
                Button("Release notes") {
                    if let release = updater.pendingRelease { NSWorkspace.shared.open(release.pageURL) }
                }
                .buttonStyle(StandardButtonStyle())
                Button(updater.canInstallInPlace ? "Download and install" : "Download") {
                    Task { await updater.downloadAndInstall() }
                }
                .buttonStyle(AccentButtonStyle())
            }
        default:
            Button("Check for updates") {
                Task { await updater.checkForUpdates(userInitiated: true) }
            }
            .buttonStyle(StandardButtonStyle())
        }
    }

    /// Release notes are Markdown; show them as readable plain text.
    static func plainNotes(_ markdown: String) -> String {
        markdown
            .replacingOccurrences(of: "\r", with: "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var text = line.trimmingCharacters(in: .whitespaces)
                while text.hasPrefix("#") { text.removeFirst() }
                if text.hasPrefix("- ") || text.hasPrefix("* ") { text = "• " + text.dropFirst(2) }
                return text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Chips that add or remove each menu bar item.
private struct MenuBarItemsCard: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 16))
                    .foregroundStyle(Fluent.textPrimary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show in the menu bar").font(.system(size: 13)).foregroundStyle(Fluent.textPrimary)
                    Text("Click an item for a live graph and the busiest apps. Task Manager keeps running in the menu bar when its window is closed.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Fluent.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(MenuBarItem.allCases) { item in
                    let on = settings.menuBarItems.contains(item)
                    Button {
                        settings.setMenuBarItem(item, shown: !on)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: on ? "checkmark" : item.symbol)
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 14)
                            Text(item.title).font(.system(size: 12.5))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(on ? Fluent.textOnAccent : Fluent.textPrimary)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: Fluent.controlRadius + 2, style: .continuous).fill(on ? Fluent.accent : Fluent.controlFill))
                        .overlay(RoundedRectangle(cornerRadius: Fluent.controlRadius + 2, style: .continuous).strokeBorder(on ? .clear : Fluent.controlStroke))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.leading, 38)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).fill(Fluent.card))
        .overlay(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).strokeBorder(Fluent.cardStroke))
    }
}
