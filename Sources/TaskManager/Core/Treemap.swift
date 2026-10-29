import CoreGraphics

/// Squarified treemap layout: each value gets a rectangle with area in proportion to it, kept as
/// close to square as possible (Bruls, Huizing and van Wijk).
enum Treemap {
    /// Rectangles in the same order as `values`. Zero and negative values get an empty rectangle.
    static func layout(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: .zero, count: values.count)
        let order = values.indices.filter { values[$0] > 0 }.sorted { values[$0] > values[$1] }
        let total = order.reduce(0) { $0 + values[$1] }
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }
        let scale = Double(rect.width * rect.height) / total
        var remaining = rect
        var row: [Int] = []
        var index = 0
        while index < order.count {
            let candidate = order[index]
            let side = Double(min(remaining.width, remaining.height))
            if row.isEmpty || worst(row + [candidate], side: side, values: values, scale: scale) <= worst(row, side: side, values: values, scale: scale) {
                row.append(candidate)
                index += 1
            } else {
                remaining = place(row, in: remaining, values: values, scale: scale, into: &result)
                row = []
            }
        }
        if !row.isEmpty { _ = place(row, in: remaining, values: values, scale: scale, into: &result) }
        return result
    }

    /// The worst aspect ratio in a row laid along a side of the given length.
    private static func worst(_ row: [Int], side: Double, values: [Double], scale: Double) -> Double {
        let areas = row.map { values[$0] * scale }
        let sum = areas.reduce(0, +)
        guard sum > 0, side > 0, let largest = areas.max(), let smallest = areas.min(), smallest > 0 else { return .infinity }
        let s2 = side * side, sum2 = sum * sum
        return max(s2 * largest / sum2, sum2 / (s2 * smallest))
    }

    /// Lays a row along the shorter side of `rect` and returns the space left over.
    private static func place(_ row: [Int], in rect: CGRect, values: [Double], scale: Double, into result: inout [CGRect]) -> CGRect {
        let area = row.reduce(0) { $0 + values[$1] * scale }
        if rect.width >= rect.height {
            // A column on the left.
            let width = CGFloat(area) / rect.height
            var y = rect.minY
            for i in row {
                let height = CGFloat(values[i] * scale) / max(width, .leastNonzeroMagnitude)
                result[i] = CGRect(x: rect.minX, y: y, width: width, height: height)
                y += height
            }
            return CGRect(x: rect.minX + width, y: rect.minY, width: max(rect.width - width, 0), height: rect.height)
        } else {
            // A row along the top.
            let height = CGFloat(area) / rect.width
            var x = rect.minX
            for i in row {
                let width = CGFloat(values[i] * scale) / max(height, .leastNonzeroMagnitude)
                result[i] = CGRect(x: x, y: rect.minY, width: width, height: height)
                x += width
            }
            return CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: max(rect.height - height, 0))
        }
    }
}
