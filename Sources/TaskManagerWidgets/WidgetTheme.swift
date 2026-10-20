import SwiftUI

/// Widget colours that follow the design chosen in Task Manager's Settings.
struct WidgetTheme {
    let design: String
    let scheme: ColorScheme

    private var dark: Bool { scheme == .dark || design == "midnight" || design == "terminal" }

    var fontDesign: Font.Design {
        switch design {
        case "terminal": return .monospaced
        case "midnight": return .rounded
        default: return .default
        }
    }

    @ViewBuilder var background: some View {
        switch design {
        case "midnight":
            LinearGradient(colors: [rgb(7, 10, 26), rgb(16, 18, 48), rgb(32, 16, 60)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "terminal":
            rgb(2, 7, 3)
        case "windows10":
            dark ? rgb(25, 25, 25) : rgb(255, 255, 255)
        case "macOS":
            dark ? rgb(36, 36, 38) : rgb(246, 246, 246)
        default:
            LinearGradient(
                colors: dark ? [rgb(36, 36, 36), rgb(28, 28, 28)] : [rgb(250, 250, 250), rgb(238, 242, 246)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    var primary: Color {
        switch design {
        case "terminal": return rgb(51, 255, 102)
        case "midnight": return rgb(241, 245, 249)
        default: return dark ? .white : Color(white: 0.08)
        }
    }

    var secondary: Color {
        switch design {
        case "terminal": return rgb(36, 186, 76)
        case "midnight": return rgb(148, 163, 184)
        default: return dark ? Color.white.opacity(0.68) : Color.black.opacity(0.58)
        }
    }

    var track: Color {
        switch design {
        case "terminal": return rgb(51, 255, 102).opacity(0.15)
        case "midnight": return Color.white.opacity(0.1)
        default: return dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
        }
    }

    func accent(_ choice: String) -> Color {
        switch choice {
        case "blue": return dark ? rgb(96, 205, 255) : rgb(0, 95, 184)
        case "purple": return dark ? rgb(195, 163, 247) : rgb(116, 77, 169)
        case "pink": return dark ? rgb(255, 138, 209) : rgb(191, 0, 119)
        case "red": return dark ? rgb(255, 153, 164) : rgb(196, 43, 28)
        case "orange": return dark ? rgb(255, 178, 122) : rgb(202, 80, 16)
        case "yellow": return dark ? rgb(255, 213, 79) : rgb(157, 93, 0)
        case "green": return dark ? rgb(108, 203, 95) : rgb(16, 124, 16)
        case "teal": return dark ? rgb(76, 214, 224) : rgb(0, 131, 138)
        case "graphite": return dark ? rgb(200, 198, 196) : rgb(93, 90, 88)
        default:
            switch design {
            case "windows10": return dark ? rgb(51, 153, 255) : rgb(0, 120, 215)
            case "macOS": return Color.accentColor
            case "midnight": return rgb(34, 211, 238)
            case "terminal": return rgb(51, 255, 102)
            default: return dark ? rgb(96, 205, 255) : rgb(0, 95, 184)
            }
        }
    }

    var cpu: Color {
        switch design {
        case "midnight": return rgb(34, 211, 238)
        case "terminal": return rgb(51, 255, 102)
        case "macOS": return .blue
        default: return dark ? rgb(56, 163, 226) : rgb(17, 125, 187)
        }
    }

    var memory: Color {
        switch design {
        case "midnight": return rgb(167, 139, 250)
        case "terminal": return rgb(160, 255, 96)
        case "macOS": return .purple
        default: return dark ? rgb(184, 98, 216) : rgb(139, 18, 174)
        }
    }

    var disk: Color {
        switch design {
        case "midnight": return rgb(163, 230, 53)
        case "terminal": return rgb(0, 229, 160)
        case "macOS": return .green
        default: return dark ? rgb(120, 196, 64) : rgb(77, 166, 12)
        }
    }

    var network: Color {
        switch design {
        case "midnight": return rgb(251, 191, 36)
        case "terminal": return rgb(255, 208, 0)
        case "macOS": return .orange
        default: return dark ? rgb(222, 137, 52) : rgb(167, 79, 1)
        }
    }

    var gpu: Color {
        switch design {
        case "midnight": return rgb(244, 114, 182)
        case "terminal": return rgb(102, 255, 204)
        case "macOS": return .teal
        default: return cpu
        }
    }

    /// Heat-map cell colour, matching the Processes page.
    func heat(_ fraction: Double) -> Color {
        let f = min(max(fraction, 0), 1)
        let stops: [(Double, Double, Double)]
        switch design {
        case "midnight": stops = [(30, 27, 75), (88, 28, 135), (219, 39, 119)]
        case "terminal": stops = [(0, 22, 8), (0, 66, 24), (20, 140, 52)]
        case "macOS": stops = dark ? [(30, 36, 50), (34, 60, 112), (48, 104, 214)] : [(240, 245, 255), (188, 212, 255), (90, 140, 245)]
        default: stops = dark ? [(57, 52, 32), (96, 76, 22), (152, 68, 22)] : [(255, 244, 196), (255, 220, 126), (250, 148, 78)]
        }
        let scaled = f * 2
        let (a, b, t) = scaled <= 1 ? (stops[0], stops[1], scaled) : (stops[1], stops[2], scaled - 1)
        return Color(.sRGB, red: (a.0 + (b.0 - a.0) * t) / 255, green: (a.1 + (b.1 - a.1) * t) / 255, blue: (a.2 + (b.2 - a.2) * t) / 255)
    }

    func temperature(_ celsius: Double) -> Color {
        switch celsius {
        case ..<60: return design == "terminal" ? rgb(51, 255, 102) : (dark ? rgb(108, 203, 95) : rgb(16, 124, 16))
        case ..<80: return dark ? rgb(255, 204, 77) : rgb(194, 140, 0)
        case ..<95: return dark ? rgb(255, 153, 77) : rgb(217, 97, 13)
        default: return dark ? rgb(255, 110, 100) : rgb(196, 43, 28)
        }
    }

    private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255)
    }
}
