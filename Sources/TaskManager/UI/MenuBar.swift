import AppKit
import SwiftUI

struct MenuBarLabel: View {
    @Environment(Monitor.self) private var monitor
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("CPU \(Fmt.wholePercent(monitor.system.cpu.total))")
            .monospacedDigit()
            .onAppear {
                if state.openMainWindow == nil {
                    state.openMainWindow = { openWindow(id: AppState.mainWindowID) }
                }
            }
    }
}

struct MenuBarContent: View {
    @Environment(Monitor.self) private var monitor
    @Environment(AppState.self) private var state

    var body: some View {
        let s = monitor.system
        Button("Open Task Manager") { state.bringToFront() }
        Divider()
        Text("CPU: \(Fmt.wholePercent(s.cpu.total))")
        Text("Memory: \(Fmt.gigabytes(s.memory.used)) of \(Fmt.gigabytes(s.memory.total)) (\(Fmt.wholePercent(s.memory.usedFraction)))")
        if let gpu = s.gpu {
            Text("GPU: \(Fmt.wholePercent(gpu.utilization))")
        }
        Divider()
        Button("Quit Task Manager") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
