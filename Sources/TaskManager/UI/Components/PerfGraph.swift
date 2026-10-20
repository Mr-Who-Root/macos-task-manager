import SwiftUI

struct GraphSeries {
    var values: [Double]
    var color: Color
    /// nil uses the design's default fill.
    var fillOpacity: Double? = nil
    var dashed = false
    /// nil uses the design's default line width.
    var lineWidth: CGFloat? = nil
}

/// A Windows Task Manager style graph: grid that scrolls with time, line + translucent fill.
struct PerfGraph: View {
    var series: [GraphSeries]
    var maxValue: Double = 1
    var tint: Color
    var phase: Int = 0
    var showGrid = true
    var gridRows = 10
    var gridColumns = 20
    var capacity = History.capacity

    var body: some View {
        let design = Fluent.design
        Canvas { context, size in
            let w = size.width, h = size.height
            if showGrid {
                var grid = Path()
                for row in 1..<gridRows {
                    let y = (h * CGFloat(row) / CGFloat(gridRows)).rounded() + 0.5
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: w, y: y))
                }
                // Vertical lines move left one sample per tick, like Windows.
                let step = w / CGFloat(capacity - 1)
                let samplesPerColumn = max(capacity / gridColumns, 1)
                let offset = CGFloat(phase % samplesPerColumn) * step
                var x = w - offset
                while x > 0 {
                    grid.move(to: CGPoint(x: x.rounded() + 0.5, y: 0))
                    grid.addLine(to: CGPoint(x: x.rounded() + 0.5, y: h))
                    x -= step * CGFloat(samplesPerColumn)
                }
                context.stroke(grid, with: .color(tint.opacity(design == .terminal ? 0.22 : 0.16)), lineWidth: 1)
            }

            let scale = maxValue > 0 ? maxValue : 1
            for s in series where s.values.count > 1 {
                let count = s.values.count
                let step = w / CGFloat(capacity - 1)
                let start = CGFloat(capacity - count) * step
                func point(_ i: Int) -> CGPoint {
                    let v = min(max(s.values[i] / scale, 0), 1)
                    return CGPoint(x: start + CGFloat(i) * step, y: h - CGFloat(v) * (h - 1))
                }
                var line = Path()
                line.move(to: point(0))
                for i in 1..<count { line.addLine(to: point(i)) }
                let fillOpacity = s.fillOpacity ?? design.graphFillOpacity
                if fillOpacity > 0 {
                    var fill = line
                    fill.addLine(to: CGPoint(x: point(count - 1).x, y: h))
                    fill.addLine(to: CGPoint(x: start, y: h))
                    fill.closeSubpath()
                    if design == .midnight {
                        context.fill(fill, with: .linearGradient(
                            Gradient(colors: [s.color.opacity(fillOpacity * 1.6), s.color.opacity(0.02)]),
                            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)
                        ))
                    } else {
                        context.fill(fill, with: .color(s.color.opacity(fillOpacity)))
                    }
                }
                let style = StrokeStyle(lineWidth: s.lineWidth ?? design.graphLineWidth, lineJoin: .round, dash: s.dashed ? [4, 3] : [])
                var lineContext = context
                if design.graphGlow {
                    lineContext.addFilter(.shadow(color: s.color.opacity(0.85), radius: 3))
                }
                lineContext.stroke(line, with: .color(s.color), style: style)
            }
        }
        .background(Fluent.graphBackground)
        .overlay(Rectangle().strokeBorder(tint, lineWidth: 1))
    }
}

/// Small grey caption row above/below a graph: "% Utilization" ... "100%".
struct GraphCaption: View {
    let leading: String
    var trailing: String = ""

    var body: some View {
        HStack {
            Text(leading)
            Spacer()
            Text(trailing)
        }
        .font(.system(size: 11.5))
        .foregroundStyle(Fluent.textSecondary)
    }
}
