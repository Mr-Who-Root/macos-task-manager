import SwiftUI

/// Settings › Design: a preview card per design, plus accent colour swatches.
struct DesignPicker: View {
    @Bindable private var store = DesignStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(AppDesign.allCases) { design in
                    DesignCard(design: design, isSelected: store.design == design) {
                        withAnimation(.easeInOut(duration: 0.2)) { store.design = design }
                    }
                }
            }
            SettingCard(systemImage: "paintpalette", title: "Accent color",
                        subtitle: "Used for selection, buttons and highlights") {
                AccentSwatches(selection: $store.accent)
            }
        }
    }
}

private struct DesignCard: View {
    let design: AppDesign
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                DesignThumbnail(design: design)
                    .frame(height: 96)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(design.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Fluent.textPrimary)
                        Text(design.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Fluent.textSecondary)
                            .lineLimit(2, reservesSpace: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(isSelected ? Fluent.accent : Fluent.textTertiary)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).fill(hovering ? Fluent.subtleHover : Fluent.card))
            .overlay(
                RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous)
                    .strokeBorder(isSelected ? Fluent.accent : Fluent.cardStroke, lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(design.title) design")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A miniature Task Manager window drawn in a design's own colours.
struct DesignThumbnail: View {
    let design: AppDesign

    var body: some View {
        let p = design.palette
        GeometryReader { geometry in
            let w = geometry.size.width
            ZStack(alignment: .topLeading) {
                background(p)
                VStack(spacing: 0) {
                    HStack(spacing: 3) {
                        ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.85)).frame(width: 5, height: 5) }
                        Spacer()
                        RoundedRectangle(cornerRadius: design.controlRadius / 2 + 1)
                            .fill(p.controlFill)
                            .overlay(RoundedRectangle(cornerRadius: design.controlRadius / 2 + 1).strokeBorder(p.controlStroke, lineWidth: 0.5))
                            .frame(width: w * 0.36, height: 7)
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 15)
                    switch design.navigation {
                    case .rail:
                        HStack(spacing: 0) {
                            rail(p)
                            content(p)
                        }
                    case .tabs:
                        tabs(p)
                        content(p)
                    case .sidebar:
                        HStack(spacing: 0) {
                            sidebar(p)
                            content(p)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(p.cardStroke, lineWidth: 1))
        .fontDesign(design.fontDesign)
    }

    @ViewBuilder
    private func background(_ p: DesignPalette) -> some View {
        if design.background == .gradient {
            LinearGradient(colors: p.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if design.background == .mica {
            p.window.overlay(LinearGradient(colors: [p.accent.opacity(0.08), .clear], startPoint: .topTrailing, endPoint: .bottomLeading))
        } else {
            p.window
        }
    }

    private func rail(_ p: DesignPalette) -> some View {
        VStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i == 0 ? p.textPrimary : p.textSecondary.opacity(0.6))
                    .frame(width: 7, height: 7)
                    .frame(width: 16, height: 12)
                    .background(RoundedRectangle(cornerRadius: 2).fill(i == 0 ? p.subtleSelected : .clear))
                    .overlay(alignment: .leading) {
                        if i == 0 { Capsule().fill(p.accent).frame(width: 1.5, height: 6) }
                    }
            }
            Spacer()
        }
        .padding(.top, 4)
        .frame(width: 22)
    }

    private func tabs(_ p: DesignPalette) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Rectangle()
                    .fill(i == 0 ? (design == .terminal ? p.accent : p.layer) : .clear)
                    .frame(width: 26, height: 9)
                    .overlay(
                        Rectangle().fill(i == 0 && design == .terminal ? p.textOnAccent : p.textSecondary.opacity(0.7))
                            .frame(width: 16, height: 2)
                    )
                    .overlay(alignment: .top) {
                        if i == 0 && design != .terminal { Rectangle().fill(p.accent).frame(height: 1) }
                    }
            }
            Spacer()
        }
        .padding(.horizontal, 6)
    }

    private func sidebar(_ p: DesignPalette) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                HStack(spacing: 3) {
                    Circle().fill(i == 0 ? p.textOnAccent : p.accent).frame(width: 4, height: 4)
                    Rectangle().fill(i == 0 ? p.textOnAccent : p.textSecondary.opacity(0.7)).frame(width: 18, height: 2)
                }
                .padding(.horizontal, 3)
                .frame(height: 8)
                .background(RoundedRectangle(cornerRadius: 2).fill(i == 0 ? p.accent : .clear))
            }
            Spacer()
        }
        .padding(.top, 2)
        .padding(.horizontal, 4)
        .frame(width: 42)
        .background(p.subtleHover)
    }

    private func content(_ p: DesignPalette) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: design.layerRadius / 2, style: .continuous)
        let rows: [(CGFloat, Double, Double)] = [(0.62, 0.05, 0.2), (0.44, 0.7, 0.9), (0.55, 0.2, 0.45), (0.38, 0.02, 0.1)]
        return VStack(alignment: .leading, spacing: 2) {
            Rectangle().fill(p.textPrimary.opacity(0.8)).frame(width: 30, height: 3).padding(.bottom, 3)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    Rectangle().fill(p.textSecondary.opacity(0.55)).frame(width: 44 * row.0, height: 2)
                    Spacer(minLength: 4)
                    Rectangle().fill(p.heat[Int(row.1 * 24)]).frame(width: 18, height: 9)
                    Rectangle().fill(p.heat[Int(row.2 * 24)]).frame(width: 22, height: 9)
                    Rectangle().fill(p.heat[1]).frame(width: 16, height: 9)
                }
            }
            Spacer(minLength: 0)
            graph(p)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(p.layer))
        .overlay(shape.strokeBorder(p.layerStroke, lineWidth: 0.5))
    }

    private func graph(_ p: DesignPalette) -> some View {
        Canvas { context, size in
            let values: [Double] = [0.2, 0.35, 0.3, 0.55, 0.4, 0.62, 0.48, 0.7, 0.52, 0.6]
            var line = Path()
            for (i, v) in values.enumerated() {
                let point = CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1), y: size.height * (1 - v))
                i == 0 ? line.move(to: point) : line.addLine(to: point)
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            context.fill(fill, with: .color(p.cpu.opacity(design.graphFillOpacity + 0.05)))
            context.stroke(line, with: .color(p.cpu), lineWidth: 1)
        }
        .frame(height: 16)
        .background(p.graphBackground)
        .overlay(Rectangle().strokeBorder(p.cpu.opacity(0.8), lineWidth: 0.5))
    }
}

private struct AccentSwatches: View {
    @Binding var selection: AccentChoice

    var body: some View {
        HStack(spacing: 7) {
            ForEach(AccentChoice.allCases) { choice in
                Button {
                    selection = choice
                } label: {
                    ZStack {
                        Circle()
                            .fill(choice.color ?? Fluent.design.palette.accent)
                            .frame(width: 18, height: 18)
                        if choice == .automatic {
                            Image(systemName: "sparkles")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Fluent.design.palette.textOnAccent)
                        }
                    }
                    .padding(2.5)
                    .overlay(Circle().strokeBorder(selection == choice ? Fluent.textPrimary : .clear, lineWidth: 1.5))
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(choice.title)
                .accessibilityLabel(choice.title)
            }
        }
    }
}
