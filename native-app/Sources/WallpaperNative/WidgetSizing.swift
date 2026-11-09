import Foundation

struct WidgetSize: Codable, Equatable {
    var width: Double
    var height: Double
    var automaticHeight: Bool? = nil
}

/// All coordinates are logical screen points, independent of Retina scale.
enum WidgetSizing {
    static func frame(position: Point, size: WidgetSize, bounds: CGSize) -> CGRect {
        CGRect(x: min(max(0, bounds.width * position.x / 100), max(0, bounds.width - size.width)),
               y: min(max(0, bounds.height * position.y / 100), max(0, bounds.height - size.height)),
               width: size.width, height: size.height)
    }

    /// Translation is measured in the fixed desktop space, with Y increasing downwards.
    static func draggedPosition(start: Point, translation: CGSize, size: WidgetSize, bounds: CGSize, cell: Double?) -> Point {
        let origin = frame(position: start, size: size, bounds: bounds).origin
        func coordinate(_ start: Double, _ delta: Double, _ extent: Double, _ length: Double) -> Double {
            let maximum = max(0, extent - length)
            let proposed = min(maximum, max(0, start + delta))
            let snapped = cell.map { (proposed / $0).rounded() * $0 } ?? proposed
            return min(maximum, max(0, snapped)) / max(1, extent) * 100
        }
        return Point(x: coordinate(origin.x, translation.width, bounds.width, size.width),
                     y: coordinate(origin.y, translation.height, bounds.height, size.height))
    }

    static func constrained(_ proposed: WidgetSize, available: WidgetSize, cell: Double?) -> WidgetSize {
        func dimension(_ value: Double, _ limit: Double) -> Double {
            let maximum = max(1, limit)
            let minimum = min(80, maximum)
            let bounded = min(maximum, max(minimum, value))
            guard let cell, cell > 0, maximum >= cell else { return bounded }
            return min(floor(maximum / cell) * cell, max(cell, (bounded / cell).rounded() * cell))
        }
        return WidgetSize(width: dimension(proposed.width, available.width), height: dimension(proposed.height, available.height))
    }
}
