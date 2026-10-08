import Foundation

struct DiskReadings: Equatable {
    let total: Double
    let available: Double
    var used: Double { max(0, total - available) }
    var percentage: Double { total > 0 ? used / total * 100 : 0 }

    static func read() -> DiskReadings? {
        guard let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
            forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskReadings(total: Double(total), available: Double(available))
    }
}

/// Disk capacity changes slowly; keep expensive purgeable-space queries apart.
struct TimedDiskReadings {
    let interval: TimeInterval
    private var lastAttempt: TimeInterval?
    private var latest: DiskReadings?
    private(set) var reads = 0

    mutating func sample(at time: TimeInterval, read: () -> DiskReadings?) -> DiskReadings? {
        if let lastAttempt, time >= lastAttempt, time - lastAttempt < interval { return latest }
        lastAttempt = time
        reads += 1
        if let value = read() { latest = value }
        return latest
    }
    mutating func reset() { lastAttempt = nil; latest = nil }
}
