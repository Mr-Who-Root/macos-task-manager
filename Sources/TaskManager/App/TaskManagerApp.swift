import AppKit
import SwiftUI

@main
struct TaskManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Task Manager", id: AppState.mainWindowID) {
            MainView()
                .environment(Monitor.shared)
                .environment(AppSettings.shared)
                .environment(AppState.shared)
                .onOpenURL { DeepLink.open($0) }
        }
        .handlesExternalEvents(matching: [])
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1140, height: 760)
        .commands { TaskManagerCommands() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DesignStore.applyAppearance()
        GlobalHotKey.shared.action = { AppState.shared.bringToFront() }
        GlobalHotKey.shared.setEnabled(AppSettings.shared.globalHotKey)
        Monitor.shared.start()
        Updater.shared.startAutomaticChecks()
        MenuBarController.shared.sync()
        #if DEBUG
        DebugHooks.run()
        #endif
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(DeepLink.open)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        AppSettings.shared.menuBarItems.isEmpty
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppState.shared.bringToFront() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Monitor.shared.appHistory.save()
        Monitor.shared.batteryLog.save()
        Monitor.shared.timeline.save()
        Monitor.shared.dataUsage.save()
        Monitor.shared.privacy.stop()
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
            Button("Why is my Mac slow?") { AppState.shared.showDiagnosis = true }
                .keyboardShortcut("d")
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
