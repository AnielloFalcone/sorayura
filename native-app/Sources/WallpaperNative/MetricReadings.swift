import AppKit
import Observation

/// A stable identity with separately observed readings. Updating CPU must not
/// invalidate a view that only reads battery, hostname or thermal state.
@MainActor @Observable
final class MetricReadings {
    var thermal = ProcessInfo.processInfo.thermalState
    var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    var cpu = 0.0
    var memory = 0.0
    var memoryUsed = 0.0
    var memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
    var memoryApp = 0.0
    var memoryWired = 0.0
    var memoryCompressed = 0.0
    var memoryCached = 0.0
    var swapUsed = 0.0
    var disk = 0.0
    var diskUsed = 0.0
    var diskTotal = 0.0
    var battery: Double?
    var charging = false
    var download = 0.0
    var upload = 0.0
    var uptime = ProcessInfo.processInfo.systemUptime
    var hostname = Host.current().localizedName ?? "MacBook"

    func update(_ sample: Metrics) {
        assign(sample.thermal, to: \.thermal)
        assign(sample.lowPower, to: \.lowPower)
        assign(sample.cpu, to: \.cpu)
        assign(sample.memory, to: \.memory)
        assign(sample.memoryUsed, to: \.memoryUsed)
        assign(sample.memoryTotal, to: \.memoryTotal)
        assign(sample.memoryApp, to: \.memoryApp)
        assign(sample.memoryWired, to: \.memoryWired)
        assign(sample.memoryCompressed, to: \.memoryCompressed)
        assign(sample.memoryCached, to: \.memoryCached)
        assign(sample.swapUsed, to: \.swapUsed)
        assign(sample.disk, to: \.disk)
        assign(sample.diskUsed, to: \.diskUsed)
        assign(sample.diskTotal, to: \.diskTotal)
        assign(sample.battery, to: \.battery)
        assign(sample.charging, to: \.charging)
        assign(sample.download, to: \.download)
        assign(sample.upload, to: \.upload)
        assign(sample.uptime, to: \.uptime)
        assign(sample.hostname, to: \.hostname)
    }

    private func assign<Value: Equatable>(_ value: Value, to key: ReferenceWritableKeyPath<MetricReadings, Value>) {
        if self[keyPath: key] != value { self[keyPath: key] = value }
    }

    func percentage(_ key: String) -> Double {
        switch key {
        case "cpu": return cpu
        case "memory": return memory
        case "disk": return disk
        case "battery": return battery ?? 100
        case "network": return (download + upload) / 1_000_000
        default: return 0
        }
    }
}

@MainActor @Observable
final class MetricHistory {
    private(set) var values: [Double] = []
    func append(_ value: Double) {
        var next = values
        next.append(value)
        if next.count > 90 { next.removeFirst(next.count - 90) }
        values = next
    }
    func reset() { values = [] }
}
