import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Transparent command-bar button that highlights on hover (Windows 11 "subtle" button).
struct SubtleButtonStyle: ButtonStyle {
    var height: CGFloat = 32
    var horizontalPadding: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        SubtleButton(configuration: configuration, height: height, horizontalPadding: horizontalPadding)
    }

    private struct SubtleButton: View {
        let configuration: Configuration
        let height: CGFloat
        let horizontalPadding: CGFloat
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? Fluent.textPrimary : Fluent.textDisabled)
                .padding(.horizontal, horizontalPadding)
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: Fluent.controlRadius, style: .continuous)
                        .fill(configuration.isPressed ? Fluent.subtlePressed : (hovering && isEnabled ? Fluent.subtleHover : .clear))
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

/// Filled accent button ("OK").
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AccentButton(configuration: configuration)
    }

    private struct AccentButton: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13))
                .foregroundStyle(isEnabled ? Fluent.textOnAccent : Fluent.textDisabled)
                .padding(.horizontal, 14)
                .frame(minWidth: 84, minHeight: 30)
                .background(
                    RoundedRectangle(cornerRadius: Fluent.controlRadius, style: .continuous)
                        .fill(isEnabled ? Fluent.accent.opacity(configuration.isPressed ? 0.8 : 1) : Fluent.subtleSelected)
                )
                .contentShape(Rectangle())
        }
    }
}

/// Standard bordered button ("Cancel", "Browse…").
struct StandardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StandardButton(configuration: configuration)
    }

    private struct StandardButton: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13))
                .foregroundStyle(isEnabled ? Fluent.textPrimary : Fluent.textDisabled)
                .padding(.horizontal, 14)
                .frame(minWidth: 84, minHeight: 30)
                .background(
                    RoundedRectangle(cornerRadius: Fluent.controlRadius, style: .continuous)
                        .fill(hovering && !configuration.isPressed ? Fluent.controlFillHover : Fluent.controlFill)
                )
                .overlay(RoundedRectangle(cornerRadius: Fluent.controlRadius, style: .continuous).strokeBorder(Fluent.controlStroke))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

struct CommandButton: View {
    let title: String
    let systemImage: String
    var isDisabled = false
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(isOn ? Fluent.efficiency : Color.primary)
                    .frame(width: 16)
                Text(title).font(.system(size: 12.5))
            }
        }
        .buttonStyle(SubtleButtonStyle())
        .disabled(isDisabled)
        .help(title)
    }
}

/// A command-bar button that opens a menu.
struct CommandBarMenu<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage).font(.system(size: 13)).frame(width: 16)
                Text(title).font(.system(size: 12.5))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Fluent.textSecondary)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(SubtleButtonStyle())
        .fixedSize()
    }
}

/// "End task", or "Restart" when Finder is selected (Finder can't be ended, only restarted).
struct EndTaskCommand: View {
    let target: RowTarget?

    var body: some View {
        if let target, target.isFinder {
            CommandButton(title: "Restart", systemImage: "arrow.clockwise") { ProcessActions.restartFinder() }
        } else {
            CommandButton(title: "End task", systemImage: "nosign", isDisabled: target == nil) {
                if let target { ProcessActions.requestEndTask(target) }
            }
        }
    }
}

struct CommandSeparator: View {
    var body: some View {
        Rectangle().fill(Fluent.divider).frame(width: 1, height: 20).padding(.horizontal, 4)
    }
}

/// Page title on the left, command buttons on the right.
struct PageHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 2) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Fluent.textPrimary)
            Spacer(minLength: 16)
            trailing
        }
        .padding(.leading, 22)
        .padding(.trailing, 14)
        .frame(height: 54)
    }
}

/// Windows 11 text box with an accent underline when focused.
struct SearchBox: View {
    @Binding var text: String
    var placeholder = "Type a name, publisher, or PID to search"
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Fluent.textSecondary)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Fluent.textTertiary))
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused(focus)
                .onExitCommand { text = "" }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(SubtleButtonStyle(height: 22, horizontalPadding: 6))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: Fluent.controlRadius + 1, style: .continuous).fill(focus.wrappedValue ? Fluent.graphBackground : Fluent.controlFill))
        .overlay(RoundedRectangle(cornerRadius: Fluent.controlRadius + 1, style: .continuous).strokeBorder(Fluent.controlStroke))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(focus.wrappedValue ? Fluent.accent : Fluent.textTertiary.opacity(0.5))
                .frame(height: focus.wrappedValue ? 2 : 1)
                .padding(.horizontal, 1)
                .clipShape(RoundedRectangle(cornerRadius: Fluent.controlRadius + 1))
        }
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = true }
    }
}

/// Settings card: icon, title and description on the left, a control on the right.
struct SettingCard<Control: View>: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 16))
                .foregroundStyle(Fluent.textPrimary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13)).foregroundStyle(Fluent.textPrimary)
                if let subtitle {
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(Fluent.textSecondary)
                }
            }
            Spacer(minLength: 16)
            control
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
        .background(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).fill(Fluent.card))
        .overlay(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).strokeBorder(Fluent.cardStroke))
    }
}

/// App or executable icon for a path, cached.
struct ProcessIcon: View {
    let path: String?
    var symbol: String?

    var body: some View {
        if let symbol {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Fluent.textSecondary)
                .padding(1)
        } else {
            Image(nsImage: IconCache.icon(for: path))
                .resizable()
                .interpolation(.high)
        }
    }
}

@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]
    private static let executable: NSImage = NSWorkspace.shared.icon(for: .unixExecutable)

    static func icon(for path: String?) -> NSImage {
        guard let path, !path.isEmpty else { return executable }
        if let image = cache[path] { return image }
        let image = FileManager.default.fileExists(atPath: path) ? NSWorkspace.shared.icon(forFile: path) : executable
        cache[path] = image
        return image
    }
}

/// Behind-window blur (Mica in Windows 11, the sidebar material in macOS).
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

/// Hands the hosting NSWindow to a closure once the view is in a window.
struct WindowConfigurator: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = HostView()
        view.onWindow = configure
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class HostView: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}

/// The app's glyph: a pulse line on a blue tile, echoing the Windows 11 Task Manager icon.
struct AppGlyph: View {
    var body: some View {
        GeometryReader { geometry in
            let s = min(geometry.size.width, geometry.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.24, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.24, green: 0.80, blue: 0.86), Color(red: 0.07, green: 0.42, blue: 0.85)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                Path { path in
                    let points: [(CGFloat, CGFloat)] = [(0.16, 0.6), (0.34, 0.6), (0.45, 0.3), (0.58, 0.76), (0.68, 0.5), (0.84, 0.5)]
                    path.addLines(points.map { CGPoint(x: $0.0 * s, y: $0.1 * s) })
                }
                .stroke(.white, style: StrokeStyle(lineWidth: max(1.3, s * 0.085), lineCap: .round, lineJoin: .round))
            }
            .frame(width: s, height: s)
        }
    }
}

/// A grey "label: value" grid used on the Performance and Properties pages.
struct KeyValueGrid: View {
    let rows: [(String, String)]
    var labelWidth: CGFloat? = nil

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 5) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.0)
                        .foregroundStyle(Fluent.textSecondary)
                        .frame(width: labelWidth, alignment: .leading)
                    Text(row.1)
                        .foregroundStyle(Fluent.textPrimary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }
        }
        .font(.system(size: 12))
    }
}
