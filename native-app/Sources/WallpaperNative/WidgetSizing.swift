import Foundation

struct WidgetSize: Codable, Equatable {
    var width: Double
    var height: Double
}

/// All coordinates are logical screen points, independent of Retina scale.
enum WidgetSizing {
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
