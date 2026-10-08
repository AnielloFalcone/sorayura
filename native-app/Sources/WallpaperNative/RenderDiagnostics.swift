import AppKit
import Metal

/// Bounded, opt-in samples from this application's command buffers only.
/// GPU elapsed time is not device utilization or a measurement of energy.
final class GPUCommandMeasurements: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0, missing = 0, errors = 0
    private var total = 0.0, maximum = 0.0
    private var recent = [Double]()
    private var cursor = 0
    func observe(_ command: MTLCommandBuffer) {
        lock.lock(); defer { lock.unlock() }
        if command.status == .error { errors += 1 }
        let start = command.gpuStartTime, end = command.gpuEndTime
        guard start > 0, end >= start else { missing += 1; return }
        let ms = (end - start) * 1000
        count += 1; total += ms; maximum = max(maximum, ms)
        if recent.count < 240 { recent.append(ms) }
        else { recent[cursor] = ms; cursor = (cursor + 1) % 240 }
    }
    func snapshot() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        let sorted = recent.sorted()
        return ["timed_commands": count, "missing_timestamps": missing, "command_errors": errors,
                "total_gpu_ms": total, "mean_gpu_ms": count > 0 ? total / Double(count) : 0,
                "max_gpu_ms": maximum,
                "recent_p95_gpu_ms": sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))],
                "recent_sample_count": sorted.count]
    }
}

/// Opt-in, bounded process diagnostics. Never changes rendering or preferences.
@MainActor enum RenderDiagnostics {
    private final class WeakView {
        weak var value: FilamentAnimationView?
        init(_ value: FilamentAnimationView) { self.value = value }
    }
    private static var views: [WeakView] = []
    private static var file: URL?
    private static var timer: Timer?
    private static var started = 0.0
    private static var duration = 600.0
    private static var events: [[String: Any]] = []
    static let gpu = GPUCommandMeasurements()
    static var appState: (() -> [String: Any])?
    private(set) static var enabled = false

    static func start(file: URL, duration: TimeInterval = 600) {
        self.file = file
        self.duration = min(3600, max(60, duration))
        started = ProcessInfo.processInfo.systemUptime
        enabled = true
        let next = Timer(timeInterval: 10, repeats: true) { _ in
            Task { @MainActor in snapshot() }
        }
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    static func event(_ name: String) {
        guard enabled else { return }
        if events.count == 64 { events.removeFirst() }
        events.append(["name": name, "uptime": ProcessInfo.processInfo.systemUptime,
                       "timestamp": ISO8601DateFormatter().string(from: Date())])
    }

    static func register(_ view: FilamentAnimationView) {
        guard enabled else { return }
        views.removeAll { $0.value == nil }
        views.append(WeakView(view))
    }

    private static func snapshot() {
        guard let file, enabled else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        views.removeAll { $0.value == nil }
        let finished = elapsed >= duration
        let record: [String: Any] = [
            "pid": getpid(), "timestamp": ISO8601DateFormatter().string(from: Date()),
            "elapsed_seconds": elapsed, "state": finished ? "completed" : "running",
            "scope": "This process's submission counters, command-buffer GPU elapsed time and attachment state; not visible pixels, device utilization or energy",
            "frame_clock_ticks": AnimationFrameClock.shared.diagnosticTicks,
            "shared_command_submissions": AnimationFrameClock.shared.diagnosticSubmissions,
            "screens_sleeping": AnimationFrameClock.shared.screensSleeping,
            "session_inactive": AnimationFrameClock.shared.sessionInactive,
            "all_windows_occluded": AnimationFrameClock.shared.allWindowsOccluded,
            "gpu": gpu.snapshot(), "lifecycle_events": events,
            "app_state": appState?() ?? [:],
            "views": views.compactMap { $0.value?.renderDiagnosticState() }
        ]
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
                .write(to: file, options: .atomic)
        } catch {
            fputs("Renderer diagnostics stopped: \(error.localizedDescription)\n", stderr)
            stop()
        }
        if finished { stop() }
    }

    private static func stop() {
        enabled = false
        timer?.invalidate(); timer = nil
        views.removeAll(); file = nil
    }
}
