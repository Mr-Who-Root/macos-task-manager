#if DEBUG
import AppKit
import SwiftUI

/// Debug-build helpers for exercising the UI without Accessibility permission.
///
///   TM_DEBUG_CLICKS="238,263;238,300"   window points from the top-left, clicked in order
///   TM_DEBUG_DELAY=4                     seconds to wait before the first click
@MainActor
enum DebugHooks {
    /// TM_DEBUG_HOVER=1 draws every table row as hovered, to test hit testing under the highlight.
    static let forceHover = ProcessInfo.processInfo.environment["TM_DEBUG_HOVER"] == "1"
    /// TM_DEBUG_SELECT=name selects the first Processes row with that name.
    static let selectName = ProcessInfo.processInfo.environment["TM_DEBUG_SELECT"]
    /// TM_DEBUG_SCROLL=bottom|center opens scrolling pages at that position.
    static let scrollAnchor: UnitPoint? = {
        switch ProcessInfo.processInfo.environment["TM_DEBUG_SCROLL"] {
        case "bottom": return .bottom
        case "center": return .center
        default: return nil
        }
    }()

    static func run() {
        let environment = ProcessInfo.processInfo.environment
        if let directory = environment["TM_DEBUG_DUMP"] {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                dump(to: URL(fileURLWithPath: directory))
            }
        }
        guard let spec = environment["TM_DEBUG_CLICKS"] else { return }
        let delay = Double(environment["TM_DEBUG_DELAY"] ?? "") ?? 4
        let points = spec.split(separator: ";").compactMap { pair -> CGPoint? in
            let parts = pair.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            return parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : nil
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            NSApp.activate()
            AppState.shared.window?.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .seconds(0.5))
            for point in points {
                await click(at: point)
                try? await Task.sleep(for: .seconds(1.2))
            }
        }
    }

    /// Writes the menu bar glyphs and panels to PNGs and lists status bar windows.
    private static func dump(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let statusWindows = NSApp.windows.filter { String(describing: type(of: $0)).contains("StatusBar") }
        print("status bar windows: \(statusWindows.count) \(statusWindows.map { NSStringFromRect($0.frame) })")
        for item in MenuBarItem.allCases {
            for style in MenuBarStyle.allCases {
                let image = MenuBarRenderer.image(item, style: style, monitor: Monitor.shared, fahrenheit: false)
                image.isTemplate = false
                write(image, to: directory.appendingPathComponent("glyph-\(item.rawValue)-\(style.rawValue).png"))
            }
            let panel = MenuBarPanel(item: item)
                .environment(Monitor.shared)
                .environment(AppSettings.shared)
                .environment(AppState.shared)
            let renderer = ImageRenderer(content: panel)
            renderer.scale = 2
            if let cgImage = renderer.cgImage {
                write(NSImage(cgImage: cgImage, size: .zero), to: directory.appendingPathComponent("panel-\(item.rawValue).png"))
            }
        }
        print("dumped to \(directory.path)")
        fflush(stdout)
    }

    private static func write(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }

    private static var eventNumber = 1000

    /// Posts a mouse move, down and up through the app's event queue, like a real click.
    private static func click(at point: CGPoint) async {
        guard let main = AppState.shared.window, let content = main.contentView else { return }
        // Points are given in the main window; deliver to whichever app window is on top there (e.g. a sheet).
        let screenPoint = main.convertPoint(toScreen: NSPoint(x: point.x, y: content.bounds.height - point.y))
        let candidates = ([main.attachedSheet, NSApp.modalWindow, NSApp.keyWindow].compactMap { $0 }) + [main]
        let window = candidates.first { $0.isVisible && $0.frame.contains(screenPoint) } ?? main
        let location = window.convertPoint(fromScreen: screenPoint)
        func post(_ type: NSEvent.EventType) {
            eventNumber += 1
            if let event = NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: eventNumber,
                clickCount: type == .mouseMoved ? 0 : 1, pressure: type == .leftMouseDown ? 1 : 0
            ) {
                NSApp.postEvent(event, atStart: false)
            }
        }
        post(.mouseMoved)
        try? await Task.sleep(for: .milliseconds(150))
        post(.leftMouseDown)
        try? await Task.sleep(for: .milliseconds(90))
        post(.leftMouseUp)
        print("debug click at \(point)")
    }
}
#else
import SwiftUI

enum DebugHooks {
    static let forceHover = false
    static let selectName: String? = nil
    static let scrollAnchor: UnitPoint? = nil
}
#endif
