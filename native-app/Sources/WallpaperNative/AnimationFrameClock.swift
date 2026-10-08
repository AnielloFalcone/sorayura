import AppKit
import Metal

@MainActor protocol AnimationFrameClient: AnyObject {
    var animationFrameRate: Int { get }
    var animationFrameActive: Bool { get }
    var animationFrameOccluded: Bool { get }
    func drawAnimationFrame()
}

/// All display passes for one tick share a submission; leases remain held until
/// that exact command completes. Dropping an uncommitted batch returns leases.
@MainActor final class MetalFrameBatch {
    let command: MTLCommandBuffer
    private var leases: [(MetalFramePool, Int)] = []
    private var submittedCallbacks: [() -> Void] = []

    init?() {
        guard let command = FilamentResources.shared?.commandQueue.makeCommandBuffer() else { return nil }
        self.command = command
    }

    func add(pool: MetalFramePool, slot: Int, submitted: @escaping () -> Void) {
        leases.append((pool, slot)); submittedCallbacks.append(submitted)
    }

    @discardableResult func commit() -> Bool {
        guard !leases.isEmpty else { return false }
        let held = leases
        command.addCompletedHandler { _ in held.forEach { $0.0.release($0.1) } }
        if RenderDiagnostics.enabled {
            let measurements = RenderDiagnostics.gpu
            command.addCompletedHandler { measurements.observe($0) }
        }
        leases.removeAll()
        command.commit()
        submittedCallbacks.forEach { $0() }
        submittedCallbacks.removeAll()
        return true
    }

    deinit { leases.forEach { $0.0.release($0.1) } }
}

/// One clock instead of an internal MTKView display link for every monitor.
/// No catch-up burst after a late tick; each client's existing rate is retained.
@MainActor final class AnimationFrameClock: NSObject {
    static let shared = AnimationFrameClock()
    static let usesIndependentFrames = CommandLine.arguments.contains("--independent-frames")
    private(set) static var currentBatch: MetalFrameBatch?

    private final class Entry {
        weak var client: (any AnimationFrameClient)?
        var next = 0.0
        var rate = 0
        init(_ client: any AnimationFrameClient) { self.client = client }
        func due(at now: Double, rate: Int) -> Bool {
            let period = 1 / Double(rate)
            if self.rate != rate { self.rate = rate; next = now }
            guard now + 0.002 >= next else { return false }
            // Advance the original phase; missed frames are skipped.
            next += period * max(1, floor((now - next) / period) + 1)
            return true
        }
    }
    private var entries: [Entry] = []
    private var timer: DispatchSourceTimer?
    private var timerRate = 0
    private let automaticallySchedule: Bool
    private(set) var screensSleeping = false
    private(set) var sessionInactive = false
    private(set) var allWindowsOccluded = false
    private(set) var diagnosticTicks = 0
    private(set) var diagnosticSubmissions = 0
    var suspended: Bool { screensSleeping || sessionInactive || allWindowsOccluded }

    init(automaticallySchedule: Bool = true, observeWorkspace: Bool = true) {
        self.automaticallySchedule = automaticallySchedule
        super.init()
        if observeWorkspace {
            let center = NSWorkspace.shared.notificationCenter
            center.addObserver(self, selector: #selector(screensSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
            center.addObserver(self, selector: #selector(screensWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
            center.addObserver(self, selector: #selector(sessionResign), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
            center.addObserver(self, selector: #selector(sessionBecome), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(windowVisibilityChanged), name: NSWindow.didChangeOcclusionStateNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(windowVisibilityChanged), name: NSWindow.didExposeNotification, object: nil)
        }
    }
    @objc private func screensSleep() { RenderDiagnostics.event("screens_sleep"); setSuspension(screensSleeping: true) }
    @objc private func screensWake() { RenderDiagnostics.event("screens_wake"); setSuspension(screensSleeping: false) }
    @objc private func sessionResign() { RenderDiagnostics.event("session_inactive"); setSuspension(sessionInactive: true) }
    @objc private func sessionBecome() { RenderDiagnostics.event("session_active"); setSuspension(sessionInactive: false) }
    @objc private func windowVisibilityChanged() { refresh() }

    func setSuspension(screensSleeping: Bool? = nil, sessionInactive: Bool? = nil) {
        if let screensSleeping { self.screensSleeping = screensSleeping }
        if let sessionInactive { self.sessionInactive = sessionInactive }
        entries.forEach { $0.rate = 0 }
        refresh()
    }
    func register(_ client: any AnimationFrameClient) {
        guard !entries.contains(where: { $0.client === client }) else { return }
        entries.append(Entry(client)); refresh()
    }
    func unregister(_ client: any AnimationFrameClient) {
        entries.removeAll { $0.client == nil || $0.client === client }; refresh()
    }
    func refresh() {
        entries.removeAll { $0.client == nil }
        let active = entries.compactMap(\.client).filter(\.animationFrameActive)
        // Desktop windows can report occlusion while still rendering on some
        // displays. Suspend only when ALL active wallpaper windows report it.
        let occluded = !active.isEmpty && active.allSatisfy(\.animationFrameOccluded)
        if allWindowsOccluded != occluded {
            entries.forEach { $0.rate = 0 }
            RenderDiagnostics.event(occluded ? "all_windows_occluded" : "window_visible")
        }
        allWindowsOccluded = occluded
        let rate = suspended ? 0 : entries.compactMap { entry -> Int? in
            guard let client = entry.client, client.animationFrameActive else { entry.rate = 0; return nil }
            return max(1, min(60, client.animationFrameRate))
        }.max() ?? 0
        guard automaticallySchedule, rate != timerRate else { return }
        timer?.cancel(); timer = nil; timerRate = rate
        guard rate > 0 else { return }
        let next = DispatchSource.makeTimerSource(queue: .main)
        let period = Int(1_000_000_000 / Double(rate))
        next.schedule(deadline: .now(), repeating: .nanoseconds(period), leeway: .milliseconds(1))
        next.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.tick(at: ProcessInfo.processInfo.systemUptime) }
        }
        timer = next; next.resume()
    }

    private func tick(at now: Double) {
        guard !suspended else { return }
        autoreleasepool {
            let due = entries.compactMap { entry -> (any AnimationFrameClient)? in
                guard let client = entry.client, client.animationFrameActive else { entry.rate = 0; return nil }
                return entry.due(at: now, rate: max(1, min(60, client.animationFrameRate))) ? client : nil
            }
            guard !due.isEmpty else { return }
            if RenderDiagnostics.enabled { diagnosticTicks += 1 }
            Self.currentBatch = MetalFrameBatch()
            defer { Self.currentBatch = nil }
            due.forEach { $0.drawAnimationFrame() }
            if Self.currentBatch?.commit() == true, RenderDiagnostics.enabled { diagnosticSubmissions += 1 }
        }
    }

    static func checkFixtures() throws {
        final class Client: AnimationFrameClient {
            var animationFrameRate = 30
            var animationFrameActive = true
            var animationFrameOccluded = false
            var frames = 0
            func drawAnimationFrame() { frames += 1 }
        }
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw SettingsError.invalid(message) }
        }
        let clock = AnimationFrameClock(automaticallySchedule: false, observeWorkspace: false)
        let a = Client(), b = Client(); b.animationFrameRate = 15
        clock.register(a); clock.register(a); clock.register(b)
        for tick in 0..<30 { clock.tick(at: Double(tick) / 30) }
        try check(a.frames == 30 && b.frames == 15, "Shared clock changed individual frame rates or duplicated a client")
        clock.tick(at: 10)
        try check(a.frames == 31 && b.frames == 16, "Late clock replayed missed frames")
        a.animationFrameActive = false; clock.refresh(); clock.tick(at: 11)
        try check(a.frames == 31 && b.frames == 17, "Paused client still draws")
        clock.setSuspension(screensSleeping: true); clock.tick(at: 12)
        clock.setSuspension(sessionInactive: true); clock.setSuspension(screensSleeping: false); clock.tick(at: 13)
        try check(b.frames == 17, "Clock resumed before both suspension reasons cleared")
        clock.setSuspension(sessionInactive: false); clock.tick(at: 14)
        try check(b.frames == 18, "Clock failed to resume")
        b.animationFrameOccluded = true; clock.refresh(); clock.tick(at: 15)
        try check(b.frames == 18 && clock.allWindowsOccluded, "Fully covered desktop still draws")
        a.animationFrameActive = true; a.animationFrameOccluded = false; clock.refresh(); clock.tick(at: 16)
        try check(b.frames == 19 && !clock.allWindowsOccluded, "One visible monitor did not resume the group")
        clock.unregister(b); clock.tick(at: 17)
        try check(b.frames == 19, "Removed client still draws")
        weak var released: Client?
        do { let transient = Client(); released = transient; clock.register(transient) }
        clock.refresh()
        try check(released == nil && clock.entries.count == 1, "Clock retains removed display views")
    }
}
