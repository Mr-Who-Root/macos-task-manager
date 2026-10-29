import AppKit
import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var state = state
        let design = Fluent.design
        layout(for: design)
            .background(DesignBackground(design: design))
            .ignoresSafeArea()
            .fontDesign(design.fontDesign == .default ? nil : design.fontDesign)
            .frame(minWidth: 820, minHeight: 540)
            .background(WindowConfigurator { window in state.attach(window) })
            .sheet(isPresented: $state.showRunTask) {
                RunNewTaskSheet().fontDesign(design.fontDesign)
            }
            .sheet(item: $state.properties) { target in
                ProcessPropertiesSheet(pid: target.pid).fontDesign(design.fontDesign)
            }
            .alert(
                state.alert?.title ?? "",
                isPresented: Binding(get: { state.alert != nil }, set: { if !$0 { state.alert = nil } }),
                presenting: state.alert
            ) { alert in
                if let action = alert.action {
                    Button(action.title, role: action.role) { action.perform() }
                    Button("Cancel", role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: { alert in
                Text(alert.message)
            }
            .onAppear {
                state.openMainWindow = { openWindow(id: AppState.mainWindowID) }
            }
    }

    @ViewBuilder
    private func layout(for design: AppDesign) -> some View {
        switch design.navigation {
        case .rail:
            VStack(spacing: 0) {
                TitleBar().frame(height: state.titleBarHeight)
                HStack(spacing: 0) {
                    NavigationRail()
                    ContentLayer { PageContainer() }
                }
            }
        case .tabs:
            VStack(spacing: 0) {
                TitleBar().frame(height: state.titleBarHeight)
                NavigationTabs()
                ContentLayer { PageContainer() }
            }
        case .sidebar:
            // The title bar must span the full width (AppKit covers a title bar that sits in a
            // column), so the sidebar's tint is painted behind it to look full height.
            VStack(spacing: 0) {
                TitleBar(showsTitle: false, contentLeading: NavigationSidebar.width).frame(height: state.titleBarHeight)
                HStack(spacing: 0) {
                    NavigationSidebar()
                    ContentLayer(edges: .top) { PageContainer() }
                }
            }
            .background(alignment: .leading) {
                ZStack {
                    VisualEffectBackground()
                    Fluent.subtleHover
                }
                .frame(width: NavigationSidebar.width)
                .overlay(alignment: .trailing) { Rectangle().fill(Fluent.divider).frame(width: 1) }
            }
        }
    }
}

/// The window background for each design.
struct DesignBackground: View {
    let design: AppDesign

    var body: some View {
        switch design.background {
        case .mica:
            ZStack {
                VisualEffectBackground()
                Fluent.window
            }
        case .solid, .sidebar:
            Fluent.window
        case .gradient:
            ZStack {
                LinearGradient(colors: design.palette.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Fluent.accent.opacity(0.16), .clear], center: .topTrailing, startRadius: 0, endRadius: 700)
                RadialGradient(colors: [design.palette.memory.opacity(0.14), .clear], center: .bottomLeading, startRadius: 0, endRadius: 600)
            }
        }
    }
}

/// The area that holds page content: a rounded "layer" in Windows 11 and Midnight,
/// a flat panel with hairline edges elsewhere.
struct ContentLayer<Content: View>: View {
    var edges: Edge.Set = [.top, .leading]
    @ViewBuilder var content: Content

    var body: some View {
        let radius = Fluent.design.layerRadius
        if radius > 0 {
            let shape = UnevenRoundedRectangle(topLeadingRadius: radius, style: .continuous)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(shape.fill(Fluent.layer))
                .clipShape(shape)
                .overlay(shape.strokeBorder(Fluent.layerStroke, lineWidth: 1).padding(.trailing, -1).padding(.bottom, -1))
        } else {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // A plain colour background would extend into the title bar's safe area and cover it.
                .background(Fluent.layer, ignoresSafeAreaEdges: [])
                .overlay(alignment: .top) {
                    if edges.contains(.top) { Rectangle().fill(Fluent.layerStroke).frame(height: 1) }
                }
                .overlay(alignment: .leading) {
                    if edges.contains(.leading) && Fluent.design.navigation == .rail { Rectangle().fill(Fluent.layerStroke).frame(width: 1) }
                }
        }
    }
}

struct PageContainer: View {
    @Environment(AppState.self) private var state

    var body: some View {
        switch state.page {
        case .processes: ProcessesPage()
        case .performance: PerformancePage()
        case .temperatures: TemperaturesPage()
        case .battery: BatteryPage()
        case .appHistory: AppHistoryPage()
        case .startup: StartupAppsPage()
        case .users: UsersPage()
        case .details: DetailsPage()
        case .services: ServicesPage()
        case .settings: SettingsPage()
        }
    }
}

struct TitleBar: View {
    var leadingInset: CGFloat?
    var showsTitle = true
    /// Where the content column starts, so the search box centres over it.
    var contentLeading: CGFloat = 0
    @Environment(AppState.self) private var state
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var state = state
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .simultaneousGesture(TapGesture(count: 2).onEnded { state.window?.performZoom(nil) })

            HStack(spacing: 10) {
                if showsTitle {
                    AppGlyph().frame(width: 16, height: 16)
                    Text("Task Manager")
                        .font(.system(size: 12))
                        .foregroundStyle(Fluent.textPrimary)
                }
                Spacer()
            }
            .padding(.leading, leadingInset ?? state.titleBarLeadingInset)
            .allowsHitTesting(false)

            SearchBox(text: $state.searchText, focus: $searchFocused)
                .frame(maxWidth: 440)
                .padding(.horizontal, showsTitle ? 220 : 40)
                .padding(.leading, contentLeading)
        }
        .onChange(of: state.searchFocusRequest) {
            searchFocused = true
        }
    }
}

struct NavigationRail: View {
    @Environment(AppState.self) private var state
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            NavButton(symbol: "line.3.horizontal", title: nil, isSelected: false, expanded: settings.navExpanded) {
                withAnimation(.snappy(duration: 0.22)) { settings.navExpanded.toggle() }
            }
            .help(settings.navExpanded ? "Collapse navigation" : "Expand navigation")
            .padding(.bottom, 4)

            ForEach(Page.allCases.filter { $0 != .settings }) { page in
                navItem(page)
            }
            Spacer(minLength: 8)
            navItem(.settings)
        }
        .padding(.horizontal, 5)
        .padding(.bottom, 6)
        .frame(width: settings.navExpanded ? 222 : 50, alignment: .leading)
    }

    private func navItem(_ page: Page) -> some View {
        NavButton(symbol: page.symbol, title: page.title, isSelected: state.page == page, expanded: settings.navExpanded,
                  badge: page == .settings && Updater.shared.pendingRelease != nil) {
            state.page = page
        }
        .help(settings.navExpanded ? "" : page.title)
    }
}

private struct NavButton: View {
    let symbol: String
    let title: String?
    let isSelected: Bool
    let expanded: Bool
    var badge = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .frame(width: 22)
                    .overlay(alignment: .topTrailing) {
                        if badge {
                            Circle().fill(Fluent.accent).frame(width: 7, height: 7).offset(x: 3, y: -2)
                        }
                    }
                if expanded, let title {
                    Text(title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .fixedSize()
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Fluent.textPrimary)
            .padding(.leading, 9)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Fluent.controlRadius + 1, style: .continuous)
                    .fill(isSelected ? Fluent.subtleSelected : (hovering ? Fluent.subtleHover : .clear))
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule().fill(Fluent.accent).frame(width: 3, height: 16)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Windows 10 style tabs across the top (bracketed in the Terminal design).
struct NavigationTabs: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Page.allCases.filter { $0 != .settings }.enumerated()), id: \.element) { index, page in
                TabButton(page: page, index: index + 1)
            }
            Spacer(minLength: 8)
            TabButton(page: .settings, index: Page.allCases.count, iconOnly: true)
        }
        .padding(.horizontal, 10)
        .frame(height: 34, alignment: .bottom)
    }

    private struct TabButton: View {
        let page: Page
        let index: Int
        var iconOnly = false
        @Environment(AppState.self) private var state
        @State private var hovering = false

        var body: some View {
            let selected = state.page == page
            let terminal = Fluent.design == .terminal
            Button {
                state.page = page
            } label: {
                Group {
                    if iconOnly {
                        Image(systemName: page.symbol)
                            .overlay(alignment: .topTrailing) {
                                if Updater.shared.pendingRelease != nil {
                                    Circle().fill(Fluent.accent).frame(width: 6, height: 6).offset(x: 3, y: -2)
                                }
                            }
                    } else {
                        Text(terminal ? "[\(index)] \(page.title.uppercased())" : page.title)
                    }
                }
                .font(.system(size: terminal ? 11.5 : 12.5))
                .foregroundStyle(terminal && selected ? Fluent.textOnAccent : (selected ? Fluent.textPrimary : Fluent.textSecondary))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background {
                    if terminal {
                        Rectangle().fill(selected ? Fluent.accent : (hovering ? Fluent.subtleHover : .clear))
                    } else if selected {
                        // A raised tab that merges into the content below.
                        Rectangle().fill(Fluent.layer)
                            .overlay(alignment: .top) { Rectangle().fill(Fluent.accent).frame(height: 2) }
                            .overlay(alignment: .leading) { Rectangle().fill(Fluent.layerStroke).frame(width: 1) }
                            .overlay(alignment: .trailing) { Rectangle().fill(Fluent.layerStroke).frame(width: 1) }
                            .padding(.bottom, -1)
                    } else if hovering {
                        Rectangle().fill(Fluent.subtleHover)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(page.title)
            .zIndex(selected ? 1 : 0)
        }
    }
}

/// macOS source-list sidebar that runs the full height of the window.
struct NavigationSidebar: View {
    static let width: CGFloat = 214
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header("Monitor")
            ForEach([Page.processes, .performance, .temperatures, .battery, .appHistory]) { row($0) }
            header("System").padding(.top, 10)
            ForEach([Page.startup, .users, .details, .services]) { row($0) }
            Spacer(minLength: 8)
            row(.settings)
        }
        .padding(.top, 2)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .frame(width: Self.width)
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Fluent.textTertiary)
            .padding(.leading, 8)
            .padding(.bottom, 2)
    }

    private func row(_ page: Page) -> some View {
        let selected = state.page == page
        return Button {
            state.page = page
        } label: {
            HStack(spacing: 8) {
                Image(systemName: page.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Fluent.textOnAccent : Fluent.accent)
                    .frame(width: 20)
                Text(page.title)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Fluent.textOnAccent : Fluent.textPrimary)
                Spacer(minLength: 0)
                if page == .settings && Updater.shared.pendingRelease != nil {
                    Circle().fill(selected ? Fluent.textOnAccent : Fluent.accent).frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? Fluent.accent : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
