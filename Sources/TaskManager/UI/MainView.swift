import AppKit
import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            TitleBar()
                .frame(height: state.titleBarHeight)
            HStack(spacing: 0) {
                NavigationRail()
                ContentLayer {
                    PageContainer()
                }
            }
        }
        .background(MicaBackground())
        .ignoresSafeArea()
        .frame(minWidth: 820, minHeight: 540)
        .background(WindowConfigurator { window in state.attach(window) })
        .sheet(isPresented: $state.showRunTask) {
            RunNewTaskSheet()
        }
        .sheet(item: $state.properties) { target in
            ProcessPropertiesSheet(pid: target.pid)
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
}

/// The lighter rounded "layer" that holds page content, like Windows 11 apps.
struct ContentLayer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 8, style: .continuous)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(shape.fill(Fluent.layer))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Fluent.layerStroke, lineWidth: 1).padding(.trailing, -1).padding(.bottom, -1))
    }
}

struct PageContainer: View {
    @Environment(AppState.self) private var state

    var body: some View {
        switch state.page {
        case .processes: ProcessesPage()
        case .performance: PerformancePage()
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
                AppGlyph().frame(width: 16, height: 16)
                Text("Task Manager")
                    .font(.system(size: 12))
                    .foregroundStyle(Fluent.textPrimary)
                Spacer()
            }
            .padding(.leading, state.titleBarLeadingInset)
            .allowsHitTesting(false)

            SearchBox(text: $state.searchText, focus: $searchFocused)
                .frame(maxWidth: 440)
                .padding(.horizontal, 220)
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
                RoundedRectangle(cornerRadius: 5, style: .continuous)
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
