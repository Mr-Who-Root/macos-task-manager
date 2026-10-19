import SwiftUI

struct GraphSeries {
    var values: [Double]
    var color: Color
    var fillOpacity: Double = 0.12
    var dashed = false
    var lineWidth: CGFloat = 1.2
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
                context.stroke(grid, with: .color(tint.opacity(0.16)), lineWidth: 1)
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
                if s.fillOpacity > 0 {
                    var fill = line
                    fill.addLine(to: CGPoint(x: point(count - 1).x, y: h))
                    fill.addLine(to: CGPoint(x: start, y: h))
                    fill.closeSubpath()
                    context.fill(fill, with: .color(s.color.opacity(s.fillOpacity)))
                }
                let style = StrokeStyle(lineWidth: s.lineWidth, lineJoin: .round, dash: s.dashed ? [4, 3] : [])
                context.stroke(line, with: .color(s.color), style: style)
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
