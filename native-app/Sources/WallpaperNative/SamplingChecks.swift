import AppKit
import Darwin

enum SamplingChecks {
    static func run() throws {
        func check(_ value: Bool, _ message: String) throws {
            if !value { throw SettingsError.invalid(message) }
        }
        var cache = TimedDiskReadings(interval: 30)
        let first = DiskReadings(total: 100, available: 20)
        let second = DiskReadings(total: 100, available: 30)
        var calls = 0
        func read() -> DiskReadings { calls += 1; return calls == 1 ? first : second }
        try check(cache.sample(at: 0, read: read) == first, "Initial disk read missing")
        for tick in 1..<30 {
            try check(cache.sample(at: Double(tick), read: read) == first, "Disk snapshot changed before expiry")
        }
        try check(calls == 1 && cache.reads == 1, "Every-second disk queries remain")
        try check(cache.sample(at: 30, read: read) == second && calls == 2, "Expired disk snapshot not refreshed")
        try check(cache.sample(at: 60, read: { calls += 1; return nil }) == second, "Failed refresh lost last valid disk reading")
        _ = cache.sample(at: 61, read: read)
        try check(calls == 3, "Failed disk queries retried every second")
        cache.reset()
        try check(cache.sample(at: 62, read: read) == second && calls == 4, "Reset did not force a fresh disk reading")
        _ = cache.sample(at: 1, read: read)
        try check(calls == 5, "Clock reset left disk snapshot stale")
        try check(first.used == 80 && first.percentage == 80, "Disk value semantics changed")
        print("Sampling checks passed: expiry, failure cooldown, cached values and reset")
    }

    static func benchmark() throws {
        func cpuSeconds() -> Double {
            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }
        var result: [[String: Any]] = []
        for (label, interval) in [("disk-every-sample", 0.0), ("disk-cached-30s", 30.0)] {
            let sampler = MetricsSampler(diskRefreshInterval: interval)
            let coldStart = ProcessInfo.processInfo.systemUptime
            _ = sampler.sample()
            let coldMs = (ProcessInfo.processInfo.systemUptime - coldStart) * 1000
            var wall: [Double] = [], cpu: [Double] = []
            for _ in 0..<8 {
                let began = ProcessInfo.processInfo.systemUptime, cpuBefore = cpuSeconds()
                let reading = autoreleasepool { sampler.sample() }
                guard reading.diskTotal > 0 else { throw SettingsError.invalid("No disk reading for benchmark") }
                cpu.append((cpuSeconds() - cpuBefore) * 1000)
                wall.append((ProcessInfo.processInfo.systemUptime - began) * 1000)
            }
            result.append(["label":label, "warm_samples":8, "disk_queries":sampler.diskQueries,
                           "cold_wall_ms":coldMs, "warm_wall_mean_ms":wall.reduce(0,+)/8,
                           "warm_cpu_mean_ms":cpu.reduce(0,+)/8, "warm_wall_max_ms":wall.max()!])
        }
        let object: [String: Any] = ["scope":"Small serial sampler benchmark; no UI, GPU, agent readers or preference writes; warm calls in a burst, not a whole-app CPU comparison", "results":result]
        print(String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
