import Foundation

struct AgentRankingPage {
    let total: Int
    let size: Int
    let requested: Int
    var count: Int { max(1, (total + size - 1) / size) }
    var index: Int { min(count - 1, max(0, requested)) }
    var range: Range<Int> { let start = index * size; return start..<min(total, start + size) }
    static func pageSize(expanded: Bool, height: Double?) -> Int {
        let preferred = expanded ? 6 : 3
        guard let height else { return preferred }
        return max(1, min(preferred, Int((height - 105) / 22)))
    }
    static func action(at point: CGPoint, width: Double) -> Int? {
        // Widget padding (16), title (20), then the AgentWidget spacing (10).
        guard (46..<70).contains(point.y) else { return nil }
        if (16..<40).contains(point.x) { return -1 }
        if ((width - 40)..<(width - 16)).contains(point.x) { return 1 }
        return nil
    }
}
