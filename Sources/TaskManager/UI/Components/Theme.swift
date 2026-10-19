import AppKit
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

/// Windows 11 (Fluent) design tokens.
enum Fluent {
    static let textPrimary = Color(light: rgb(0, 0, 0, 0.9), dark: rgb(255, 255, 255))
    static let textSecondary = Color(light: rgb(0, 0, 0, 0.61), dark: rgb(255, 255, 255, 0.79))
    static let textTertiary = Color(light: rgb(0, 0, 0, 0.45), dark: rgb(255, 255, 255, 0.54))
    static let textDisabled = Color(light: rgb(0, 0, 0, 0.36), dark: rgb(255, 255, 255, 0.36))
    static let accent = Color(light: rgb(0, 95, 184), dark: rgb(96, 205, 255))
    static let textOnAccent = Color(light: rgb(255, 255, 255), dark: rgb(0, 0, 0))

    static let micaTint = Color(light: rgb(238, 242, 246, 0.84), dark: rgb(32, 32, 32, 0.86))
    static let layer = Color(light: rgb(255, 255, 255, 0.55), dark: rgb(58, 58, 58, 0.32))
    static let layerStroke = Color(light: rgb(0, 0, 0, 0.07), dark: rgb(0, 0, 0, 0.3))
    static let card = Color(light: rgb(255, 255, 255, 0.72), dark: rgb(255, 255, 255, 0.05))
    static let cardStroke = Color(light: rgb(0, 0, 0, 0.06), dark: rgb(0, 0, 0, 0.2))

    static let subtleHover = Color(light: rgb(0, 0, 0, 0.037), dark: rgb(255, 255, 255, 0.061))
    static let subtlePressed = Color(light: rgb(0, 0, 0, 0.024), dark: rgb(255, 255, 255, 0.042))
    static let subtleSelected = Color(light: rgb(0, 0, 0, 0.056), dark: rgb(255, 255, 255, 0.084))
    static let rowSelected = Color(light: rgb(0, 95, 184, 0.13), dark: rgb(96, 205, 255, 0.16))
    static let rowHover = Color(light: rgb(0, 0, 0, 0.045), dark: rgb(255, 255, 255, 0.06))
    static let divider = Color(light: rgb(0, 0, 0, 0.08), dark: rgb(255, 255, 255, 0.08))

    static let controlFill = Color(light: rgb(255, 255, 255, 0.7), dark: rgb(255, 255, 255, 0.061))
    static let controlFillHover = Color(light: rgb(249, 249, 249, 0.5), dark: rgb(255, 255, 255, 0.084))
    static let controlStroke = Color(light: rgb(0, 0, 0, 0.1), dark: rgb(255, 255, 255, 0.09))
    static let graphBackground = Color(light: rgb(255, 255, 255, 0.9), dark: rgb(28, 28, 28, 0.9))
    static let efficiency = Color(light: rgb(16, 124, 16), dark: rgb(108, 203, 95))
}

/// Performance-tab colours, matching Windows Task Manager.
enum ResourceColor {
    static let cpu = Color(light: rgb(17, 125, 187), dark: rgb(56, 163, 226))
    static let memory = Color(light: rgb(139, 18, 174), dark: rgb(184, 98, 216))
    static let disk = Color(light: rgb(77, 166, 12), dark: rgb(120, 196, 64))
    static let network = Color(light: rgb(167, 79, 1), dark: rgb(222, 137, 52))
    static let gpu = Color(light: rgb(17, 125, 187), dark: rgb(56, 163, 226))
}

/// The yellow → orange heat map used for resource cells on the Processes tab.
enum Heat {
    private static let steps = 24
    private static let light: [(Double, (Double, Double, Double))] = [
        (0.00, (255, 244, 196)), (0.10, (255, 236, 170)), (0.30, (255, 220, 126)),
        (0.60, (255, 194, 92)), (1.00, (250, 148, 78)),
    ]
    private static let dark: [(Double, (Double, Double, Double))] = [
        (0.00, (57, 52, 32)), (0.10, (74, 62, 28)), (0.30, (96, 76, 22)),
        (0.60, (124, 82, 18)), (1.00, (152, 68, 22)),
    ]
    private static let palette: [Color] = (0...steps).map { i in
        let f = Double(i) / Double(steps)
        return Color(light: interpolate(light, f), dark: interpolate(dark, f))
    }

    static func color(_ fraction: Double) -> Color {
        let f = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        return palette[Int((f * Double(steps)).rounded())]
    }

    private static func interpolate(_ stops: [(Double, (Double, Double, Double))], _ f: Double) -> NSColor {
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
}
