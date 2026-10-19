import AppKit
import SwiftUI

@main
struct TaskManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("showMenuBarCPU") private var showMenuBarCPU = false

    var body: some Scene {
        Window("Task Manager", id: AppState.mainWindowID) {
            MainView()
                .environment(Monitor.shared)
                .environment(AppSettings.shared)
                .environment(AppState.shared)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1140, height: 760)
        .commands { TaskManagerCommands() }

        MenuBarExtra(isInserted: $showMenuBarCPU) {
            MenuBarContent()
                .environment(Monitor.shared)
                .environment(AppState.shared)
        } label: {
            MenuBarLabel()
                .environment(Monitor.shared)
                .environment(AppState.shared)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.shared.theme.apply()
        GlobalHotKey.shared.action = { AppState.shared.bringToFront() }
        GlobalHotKey.shared.setEnabled(AppSettings.shared.globalHotKey)
        Monitor.shared.start()
        Updater.shared.startAutomaticChecks()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !AppSettings.shared.showMenuBarCPU
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppState.shared.bringToFront() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Monitor.shared.appHistory.save()
    }
}

struct TaskManagerCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Run new task…") { AppState.shared.showRunTask = true }
                .keyboardShortcut("n")
        }
        CommandGroup(after: .textEditing) {
            Button("Search") { AppState.shared.searchFocusRequest += 1 }
                .keyboardShortcut("f")
        }
        CommandGroup(before: .toolbar) {
            ForEach(Page.allCases) { page in
                Button(page.title) { AppState.shared.page = page }
                    .keyboardShortcut(page.shortcut)
            }
            Divider()
            Button("Refresh now") { Monitor.shared.refreshNow() }
                .keyboardShortcut("r")
            Picker("Update speed", selection: Binding(
                get: { AppSettings.shared.updateSpeed },
                set: { AppSettings.shared.updateSpeed = $0 }
            )) {
                ForEach(UpdateSpeed.allCases) { Text($0.title).tag($0) }
            }
            Divider()
        }
        CommandMenu("Process") {
            Button("End task") { AppState.shared.endTaskRequest += 1 }
                .keyboardShortcut(.delete, modifiers: .command)
        }
    }
}
