import AppKit
import Observation
import SwiftUI

extension Color {
    /// A colour that switches with the effective appearance (light/dark).
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

private func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: Double = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

private func pair(_ light: NSColor, _ dark: NSColor) -> Color { Color(light: light, dark: dark) }
private func fixed(_ color: NSColor) -> Color { Color(light: color, dark: color) }

// MARK: - Designs

enum NavigationLayout {
    case rail       // Windows 11: collapsible icon rail on the left
    case tabs       // Windows 10 / terminal: tabs across the top
    case sidebar    // macOS: full-height source-list sidebar
}

enum BackgroundStyle {
    case mica       // behind-window blur with a tint
    case solid
    case gradient
    case sidebar    // vibrant sidebar, solid content
}

/// A whole look for the app: colours, shapes, type and navigation.
enum AppDesign: String, CaseIterable, Identifiable, Sendable {
    case windows11, windows10, macOS, midnight, terminal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .windows11: return "Windows 11"
        case .windows10: return "Windows 10"
        case .macOS: return "macOS"
        case .midnight: return "Midnight"
        case .terminal: return "Terminal"
        }
    }

    var subtitle: String {
        switch self {
        case .windows11: return "Fluent, Mica and a navigation rail"
        case .windows10: return "Flat and classic, with tabs"
        case .macOS: return "Native sidebar and system accent"
        case .midnight: return "Deep blue glass with neon graphs"
        case .terminal: return "Green phosphor on black"
        }
    }

    var navigation: NavigationLayout {
        switch self {
        case .windows11, .midnight: return .rail
        case .windows10, .terminal: return .tabs
        case .macOS: return .sidebar
        }
    }

    var background: BackgroundStyle {
        switch self {
        case .windows11: return .mica
        case .windows10, .terminal: return .solid
        case .macOS: return .sidebar
        case .midnight: return .gradient
        }
    }

    /// Designs that only exist in dark form override the light/dark theme setting.
    var isAlwaysDark: Bool { self == .midnight || self == .terminal }

    var controlRadius: CGFloat {
        switch self {
        case .windows11: return 4
        case .windows10, .terminal: return 0
        case .macOS: return 6
        case .midnight: return 8
        }
    }

    var cardRadius: CGFloat {
        switch self {
        case .windows11: return 6
        case .windows10, .terminal: return 0
        case .macOS: return 10
        case .midnight: return 12
        }
    }

    var layerRadius: CGFloat {
        switch self {
        case .windows11: return 8
        case .midnight: return 14
        default: return 0
        }
    }

    var fontDesign: Font.Design {
        switch self {
        case .terminal: return .monospaced
        case .midnight: return .rounded
        default: return .default
        }
    }

    var graphLineWidth: CGFloat {
        switch self {
        case .macOS: return 1.6
        case .midnight: return 1.8
        default: return 1.2
        }
    }

    var graphFillOpacity: Double {
        switch self {
        case .macOS: return 0.18
        case .midnight: return 0.22
        case .terminal: return 0.1
        default: return 0.12
        }
    }

    var graphGlow: Bool { self == .midnight || self == .terminal }

    var palette: DesignPalette {
        switch self {
        case .windows11: return .windows11
        case .windows10: return .windows10
        case .macOS: return .macOS
        case .midnight: return .midnight
        case .terminal: return .terminal
        }
    }
}

enum AccentChoice: String, CaseIterable, Identifiable, Sendable {
    case automatic, blue, purple, pink, red, orange, yellow, green, teal, graphite

    var id: String { rawValue }

    var title: String { self == .automatic ? "Design default" : rawValue.capitalized }

    /// Windows accent colours, in their light- and dark-mode variants.
    var color: Color? {
        switch self {
        case .automatic: return nil
        case .blue: return pair(rgb(0, 95, 184), rgb(96, 205, 255))
        case .purple: return pair(rgb(116, 77, 169), rgb(195, 163, 247))
        case .pink: return pair(rgb(191, 0, 119), rgb(255, 138, 209))
        case .red: return pair(rgb(196, 43, 28), rgb(255, 153, 164))
        case .orange: return pair(rgb(202, 80, 16), rgb(255, 178, 122))
        case .yellow: return pair(rgb(157, 93, 0), rgb(255, 213, 79))
        case .green: return pair(rgb(16, 124, 16), rgb(108, 203, 95))
        case .teal: return pair(rgb(0, 131, 138), rgb(76, 214, 224))
        case .graphite: return pair(rgb(93, 90, 88), rgb(200, 198, 196))
        }
    }
}

struct DesignPalette {
    var textPrimary: Color
    var textSecondary: Color
    var textTertiary: Color
    var textDisabled: Color
    var accent: Color
    var textOnAccent: Color
    var window: Color
    var gradient: [Color] = []
    var layer: Color
    var layerStroke: Color
    var card: Color
    var cardStroke: Color
    var subtleHover: Color
    var subtlePressed: Color
    var subtleSelected: Color
    var rowHover: Color
    var divider: Color
    var controlFill: Color
    var controlFillHover: Color
    var controlStroke: Color
    var graphBackground: Color
    var efficiency: Color
    var cpu: Color
    var memory: Color
    var disk: Color
    var network: Color
    var gpu: Color
    var thermal: Color
    /// 25 precomputed steps from cold to hot.
    var heat: [Color]

    typealias Stops = [(Double, (Double, Double, Double))]

    static func heatSteps(light: Stops, dark: Stops) -> [Color] {
        (0...24).map { i in
            let f = Double(i) / 24
            return Color(light: interpolate(light, f), dark: interpolate(dark, f))
        }
    }

    private static func interpolate(_ stops: Stops, _ f: Double) -> NSColor {
        var lower = stops[0], upper = stops[stops.count - 1]
        for (a, b) in zip(stops, stops.dropFirst()) where f >= a.0 && f <= b.0 {
            lower = a
            upper = b
            break
        }
        let t = upper.0 > lower.0 ? (f - lower.0) / (upper.0 - lower.0) : 0
        func mix(_ x: Double, _ y: Double) -> CGFloat { CGFloat((x + (y - x) * t) / 255) }
        return NSColor(srgbRed: mix(lower.1.0, upper.1.0), green: mix(lower.1.1, upper.1.1), blue: mix(lower.1.2, upper.1.2), alpha: 1)
    }

    private static let windowsHeatDark: Stops = [
        (0.00, (57, 52, 32)), (0.10, (74, 62, 28)), (0.30, (96, 76, 22)), (0.60, (124, 82, 18)), (1.00, (152, 68, 22)),
    ]

    static let windows11 = DesignPalette(
        textPrimary: pair(rgb(0, 0, 0, 0.9), rgb(255, 255, 255)),
        textSecondary: pair(rgb(0, 0, 0, 0.61), rgb(255, 255, 255, 0.79)),
        textTertiary: pair(rgb(0, 0, 0, 0.45), rgb(255, 255, 255, 0.54)),
        textDisabled: pair(rgb(0, 0, 0, 0.36), rgb(255, 255, 255, 0.36)),
        accent: pair(rgb(0, 95, 184), rgb(96, 205, 255)),
        textOnAccent: pair(rgb(255, 255, 255), rgb(0, 0, 0)),
        window: pair(rgb(238, 242, 246, 0.84), rgb(32, 32, 32, 0.86)),
        layer: pair(rgb(255, 255, 255, 0.55), rgb(58, 58, 58, 0.32)),
        layerStroke: pair(rgb(0, 0, 0, 0.07), rgb(0, 0, 0, 0.3)),
        card: pair(rgb(255, 255, 255, 0.72), rgb(255, 255, 255, 0.05)),
        cardStroke: pair(rgb(0, 0, 0, 0.06), rgb(0, 0, 0, 0.2)),
        subtleHover: pair(rgb(0, 0, 0, 0.037), rgb(255, 255, 255, 0.061)),
        subtlePressed: pair(rgb(0, 0, 0, 0.024), rgb(255, 255, 255, 0.042)),
        subtleSelected: pair(rgb(0, 0, 0, 0.056), rgb(255, 255, 255, 0.084)),
        rowHover: pair(rgb(0, 0, 0, 0.045), rgb(255, 255, 255, 0.06)),
        divider: pair(rgb(0, 0, 0, 0.08), rgb(255, 255, 255, 0.08)),
        controlFill: pair(rgb(255, 255, 255, 0.7), rgb(255, 255, 255, 0.061)),
        controlFillHover: pair(rgb(249, 249, 249, 0.5), rgb(255, 255, 255, 0.084)),
        controlStroke: pair(rgb(0, 0, 0, 0.1), rgb(255, 255, 255, 0.09)),
        graphBackground: pair(rgb(255, 255, 255, 0.9), rgb(28, 28, 28, 0.9)),
        efficiency: pair(rgb(16, 124, 16), rgb(108, 203, 95)),
        cpu: pair(rgb(17, 125, 187), rgb(56, 163, 226)),
        memory: pair(rgb(139, 18, 174), rgb(184, 98, 216)),
        disk: pair(rgb(77, 166, 12), rgb(120, 196, 64)),
        network: pair(rgb(167, 79, 1), rgb(222, 137, 52)),
        gpu: pair(rgb(17, 125, 187), rgb(56, 163, 226)),
        thermal: pair(rgb(196, 43, 28), rgb(255, 120, 100)),
        heat: heatSteps(
            light: [(0.00, (255, 244, 196)), (0.10, (255, 236, 170)), (0.30, (255, 220, 126)), (0.60, (255, 194, 92)), (1.00, (250, 148, 78))],
            dark: windowsHeatDark
        )
    )

    static let windows10 = DesignPalette(
        textPrimary: pair(rgb(0, 0, 0), rgb(255, 255, 255)),
        textSecondary: pair(rgb(0, 0, 0, 0.6), rgb(255, 255, 255, 0.7)),
        textTertiary: pair(rgb(0, 0, 0, 0.45), rgb(255, 255, 255, 0.5)),
        textDisabled: pair(rgb(0, 0, 0, 0.35), rgb(255, 255, 255, 0.35)),
        accent: pair(rgb(0, 120, 215), rgb(51, 153, 255)),
        textOnAccent: pair(rgb(255, 255, 255), rgb(255, 255, 255)),
        window: pair(rgb(255, 255, 255), rgb(25, 25, 25)),
        layer: pair(rgb(255, 255, 255), rgb(25, 25, 25)),
        layerStroke: pair(rgb(0, 0, 0, 0.12), rgb(255, 255, 255, 0.12)),
        card: pair(rgb(245, 245, 245), rgb(43, 43, 43)),
        cardStroke: pair(rgb(0, 0, 0, 0.1), rgb(255, 255, 255, 0.08)),
        subtleHover: pair(rgb(229, 243, 255), rgb(255, 255, 255, 0.08)),
        subtlePressed: pair(rgb(204, 232, 255), rgb(255, 255, 255, 0.12)),
        subtleSelected: pair(rgb(204, 232, 255), rgb(0, 120, 215, 0.35)),
        rowHover: pair(rgb(0, 120, 215, 0.07), rgb(255, 255, 255, 0.06)),
        divider: pair(rgb(0, 0, 0, 0.12), rgb(255, 255, 255, 0.12)),
        controlFill: pair(rgb(225, 225, 225), rgb(51, 51, 51)),
        controlFillHover: pair(rgb(229, 241, 251), rgb(70, 70, 70)),
        controlStroke: pair(rgb(173, 173, 173), rgb(110, 110, 110)),
        graphBackground: pair(rgb(255, 255, 255), rgb(17, 17, 17)),
        efficiency: pair(rgb(16, 124, 16), rgb(108, 203, 95)),
        cpu: pair(rgb(17, 125, 187), rgb(56, 163, 226)),
        memory: pair(rgb(139, 18, 174), rgb(184, 98, 216)),
        disk: pair(rgb(77, 166, 12), rgb(120, 196, 64)),
        network: pair(rgb(167, 79, 1), rgb(222, 137, 52)),
        gpu: pair(rgb(17, 125, 187), rgb(56, 163, 226)),
        thermal: pair(rgb(232, 17, 35), rgb(255, 100, 100)),
        heat: heatSteps(
            light: [(0.00, (255, 244, 196)), (0.10, (255, 232, 163)), (0.30, (255, 214, 120)), (0.60, (255, 186, 74)), (1.00, (249, 140, 40))],
            dark: windowsHeatDark
        )
    )

    static let macOS = DesignPalette(
        textPrimary: Color(nsColor: .labelColor),
        textSecondary: Color(nsColor: .secondaryLabelColor),
        textTertiary: Color(nsColor: .tertiaryLabelColor),
        textDisabled: Color(nsColor: .quaternaryLabelColor),
        accent: Color(nsColor: .controlAccentColor),
        textOnAccent: Color(nsColor: .alternateSelectedControlTextColor),
        window: Color(nsColor: .windowBackgroundColor),
        layer: Color(nsColor: .controlBackgroundColor),
        layerStroke: Color(nsColor: .separatorColor),
        card: pair(rgb(255, 255, 255, 0.9), rgb(255, 255, 255, 0.06)),
        cardStroke: Color(nsColor: .separatorColor),
        subtleHover: pair(rgb(0, 0, 0, 0.05), rgb(255, 255, 255, 0.07)),
        subtlePressed: pair(rgb(0, 0, 0, 0.08), rgb(255, 255, 255, 0.1)),
        subtleSelected: pair(rgb(0, 0, 0, 0.08), rgb(255, 255, 255, 0.1)),
        rowHover: pair(rgb(0, 0, 0, 0.04), rgb(255, 255, 255, 0.05)),
        divider: Color(nsColor: .separatorColor),
        controlFill: pair(rgb(255, 255, 255), rgb(255, 255, 255, 0.08)),
        controlFillHover: pair(rgb(246, 246, 246), rgb(255, 255, 255, 0.12)),
        controlStroke: pair(rgb(0, 0, 0, 0.12), rgb(255, 255, 255, 0.12)),
        graphBackground: Color(nsColor: .controlBackgroundColor),
        efficiency: Color(nsColor: .systemGreen),
        cpu: Color(nsColor: .systemBlue),
        memory: Color(nsColor: .systemPurple),
        disk: Color(nsColor: .systemGreen),
        network: Color(nsColor: .systemOrange),
        gpu: Color(nsColor: .systemTeal),
        thermal: Color(nsColor: .systemRed),
        heat: heatSteps(
            light: [(0.00, (240, 245, 255)), (0.10, (222, 234, 255)), (0.30, (188, 212, 255)), (0.60, (140, 180, 255)), (1.00, (90, 140, 245))],
            dark: [(0.00, (30, 36, 50)), (0.10, (32, 46, 76)), (0.30, (34, 60, 112)), (0.60, (38, 80, 160)), (1.00, (48, 104, 214))]
        )
    )

    static let midnight = DesignPalette(
        textPrimary: fixed(rgb(241, 245, 249)),
        textSecondary: fixed(rgb(148, 163, 184)),
        textTertiary: fixed(rgb(100, 116, 139)),
        textDisabled: fixed(rgb(71, 85, 105)),
        accent: fixed(rgb(34, 211, 238)),
        textOnAccent: fixed(rgb(2, 6, 23)),
        window: fixed(rgb(9, 12, 30)),
        gradient: [fixed(rgb(7, 10, 26)), fixed(rgb(16, 18, 48)), fixed(rgb(32, 16, 60))],
        layer: fixed(rgb(255, 255, 255, 0.035)),
        layerStroke: fixed(rgb(255, 255, 255, 0.09)),
        card: fixed(rgb(255, 255, 255, 0.045)),
        cardStroke: fixed(rgb(255, 255, 255, 0.09)),
        subtleHover: fixed(rgb(255, 255, 255, 0.06)),
        subtlePressed: fixed(rgb(255, 255, 255, 0.04)),
        subtleSelected: fixed(rgb(34, 211, 238, 0.14)),
        rowHover: fixed(rgb(255, 255, 255, 0.05)),
        divider: fixed(rgb(255, 255, 255, 0.08)),
        controlFill: fixed(rgb(255, 255, 255, 0.06)),
        controlFillHover: fixed(rgb(255, 255, 255, 0.1)),
        controlStroke: fixed(rgb(255, 255, 255, 0.12)),
        graphBackground: fixed(rgb(2, 6, 23, 0.6)),
        efficiency: fixed(rgb(52, 211, 153)),
        cpu: fixed(rgb(34, 211, 238)),
        memory: fixed(rgb(167, 139, 250)),
        disk: fixed(rgb(163, 230, 53)),
        network: fixed(rgb(251, 191, 36)),
        gpu: fixed(rgb(244, 114, 182)),
        thermal: fixed(rgb(251, 113, 133)),
        heat: heatSteps(
            light: [(0.00, (30, 27, 75)), (0.10, (49, 30, 110)), (0.30, (88, 28, 135)), (0.60, (147, 30, 140)), (1.00, (219, 39, 119))],
            dark: [(0.00, (30, 27, 75)), (0.10, (49, 30, 110)), (0.30, (88, 28, 135)), (0.60, (147, 30, 140)), (1.00, (219, 39, 119))]
        )
    )

    static let terminal = DesignPalette(
        textPrimary: fixed(rgb(51, 255, 102)),
        textSecondary: fixed(rgb(36, 186, 76)),
        textTertiary: fixed(rgb(24, 128, 52)),
        textDisabled: fixed(rgb(18, 90, 38)),
        accent: fixed(rgb(51, 255, 102)),
        textOnAccent: fixed(rgb(0, 0, 0)),
        window: fixed(rgb(2, 7, 3)),
        layer: fixed(rgb(4, 12, 6)),
        layerStroke: fixed(rgb(51, 255, 102, 0.25)),
        card: fixed(rgb(51, 255, 102, 0.04)),
        cardStroke: fixed(rgb(51, 255, 102, 0.25)),
        subtleHover: fixed(rgb(51, 255, 102, 0.08)),
        subtlePressed: fixed(rgb(51, 255, 102, 0.05)),
        subtleSelected: fixed(rgb(51, 255, 102, 0.14)),
        rowHover: fixed(rgb(51, 255, 102, 0.07)),
        divider: fixed(rgb(51, 255, 102, 0.18)),
        controlFill: fixed(rgb(51, 255, 102, 0.05)),
        controlFillHover: fixed(rgb(51, 255, 102, 0.1)),
        controlStroke: fixed(rgb(51, 255, 102, 0.35)),
        graphBackground: fixed(rgb(0, 0, 0)),
        efficiency: fixed(rgb(51, 255, 102)),
        cpu: fixed(rgb(51, 255, 102)),
        memory: fixed(rgb(160, 255, 96)),
        disk: fixed(rgb(0, 229, 160)),
        network: fixed(rgb(255, 208, 0)),
        gpu: fixed(rgb(102, 255, 204)),
        thermal: fixed(rgb(255, 176, 0)),
        heat: heatSteps(
            light: [(0.00, (0, 22, 8)), (0.10, (0, 40, 14)), (0.30, (0, 66, 24)), (0.60, (6, 100, 36)), (1.00, (20, 140, 52))],
            dark: [(0.00, (0, 22, 8)), (0.10, (0, 40, 14)), (0.30, (0, 66, 24)), (0.60, (6, 100, 36)), (1.00, (20, 140, 52))]
        )
    )
}

/// The chosen design and accent. Kept outside the main actor so every view
/// (and Canvas renderers) can read colours; SwiftUI observes the reads.
@Observable
final class DesignStore: @unchecked Sendable {
    static let shared = DesignStore()

    var design: AppDesign {
        didSet {
            UserDefaults.standard.set(design.rawValue, forKey: "design")
            Task { @MainActor in DesignStore.applyAppearance() }
        }
    }
    var accent: AccentChoice {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: "accent") }
    }

    private init() {
        design = AppDesign(rawValue: UserDefaults.standard.string(forKey: "design") ?? "") ?? .windows11
        accent = AccentChoice(rawValue: UserDefaults.standard.string(forKey: "accent") ?? "") ?? .automatic
    }

    /// Dark-only designs force dark mode; the others follow the theme setting.
    @MainActor static func applyAppearance() {
        if shared.design.isAlwaysDark {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        } else {
            AppSettings.shared.theme.apply()
        }
    }
}

// MARK: - Tokens

/// Colour and shape tokens for the current design. (Named after Windows 11's
/// Fluent system, which was the first design.)
enum Fluent {
    static var design: AppDesign { DesignStore.shared.design }
    private static var palette: DesignPalette { design.palette }

    static var textPrimary: Color { palette.textPrimary }
    static var textSecondary: Color { palette.textSecondary }
    static var textTertiary: Color { palette.textTertiary }
    static var textDisabled: Color { palette.textDisabled }
    static var accent: Color { DesignStore.shared.accent.color ?? palette.accent }
    static var textOnAccent: Color { DesignStore.shared.accent == .automatic ? palette.textOnAccent : Color(light: .white, dark: .black) }
    static var window: Color { palette.window }
    static var layer: Color { palette.layer }
    static var layerStroke: Color { palette.layerStroke }
    static var card: Color { palette.card }
    static var cardStroke: Color { palette.cardStroke }
    static var subtleHover: Color { palette.subtleHover }
    static var subtlePressed: Color { palette.subtlePressed }
    static var subtleSelected: Color { palette.subtleSelected }
    static var rowSelected: Color { accent.opacity(design == .terminal ? 0.22 : 0.16) }
    static var rowHover: Color { palette.rowHover }
    static var divider: Color { palette.divider }
    static var controlFill: Color { palette.controlFill }
    static var controlFillHover: Color { palette.controlFillHover }
    static var controlStroke: Color { palette.controlStroke }
    static var graphBackground: Color { palette.graphBackground }
    static var efficiency: Color { palette.efficiency }

    static var controlRadius: CGFloat { design.controlRadius }
    static var cardRadius: CGFloat { design.cardRadius }
}

/// Performance-tab colours for the current design.
enum ResourceColor {
    static var cpu: Color { Fluent.design.palette.cpu }
    static var memory: Color { Fluent.design.palette.memory }
    static var disk: Color { Fluent.design.palette.disk }
    static var network: Color { Fluent.design.palette.network }
    static var gpu: Color { Fluent.design.palette.gpu }
    static var thermal: Color { Fluent.design.palette.thermal }
}

/// The heat map used for resource cells on the Processes tab.
enum Heat {
    static func color(_ fraction: Double, in design: AppDesign? = nil) -> Color {
        let steps = (design ?? Fluent.design).palette.heat
        let f = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        return steps[Int((f * Double(steps.count - 1)).rounded())]
    }
}
