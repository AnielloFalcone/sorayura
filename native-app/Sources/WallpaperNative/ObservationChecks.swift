import Foundation
import Observation
import SwiftUI

private final class ChangeProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var changes = 0
    func signal() { lock.lock(); changes += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return changes }
}

/// Regression checks for the dependency boundaries, using the actual model.
/// No timers, app launch, local transcripts or persisted preference writes.
@MainActor enum ObservationChecks {
    static func run() throws {
        func check(_ passed: Bool, _ message: String) throws {
            if !passed { throw SettingsError.invalid(message) }
        }
        func observe(_ read: () -> Void) -> ChangeProbe {
            let probe = ChangeProbe()
            withObservationTracking(read, onChange: { probe.signal() })
            return probe
        }
        let model = Model.isolated()
        var sample = Metrics()
        sample.cpu = 21; sample.memory = 60; sample.battery = 80
        sample.download = 1_000_000; sample.upload = 250_000
        model.applySample(sample)

        let settings = observe { _ = model.prefs.layout; _ = model.savedPresets; _ = model.storageMessage }
        let agents = observe { _ = model.agentUsage; _ = model.liveAgents; _ = model.codexAccount; _ = model.updatingCounters }
        let music = observe { _ = model.spotify }
        let apps = observe { _ = model.appPresence }
        let memoryGauge = observe { _ = model.metrics.memory; _ = model.metrics.memoryUsed; _ = model.severity("memory") }
        let battery = observe { _ = model.metrics.battery; _ = model.metrics.charging }
        let thermal = observe { _ = model.metrics.thermal; _ = model.metrics.lowPower }
        let device = observe { _ = model.metrics.hostname }
        let cpu = observe { _ = model.metrics.cpu; _ = model.severity("cpu") }
        let cpuHistory = observe { _ = model.history(for: "cpu") }
        let memoryHistory = observe { _ = model.history(for: "memory") }
        sample.cpu = 60; sample.uptime += 1
        model.applySample(sample)
        try check(cpu.count == 1 && cpuHistory.count == 1 && memoryHistory.count == 1,
                  "CPU and sampled histories did not notify their consumers")
        try check([settings, agents, music, apps, memoryGauge, battery, thermal, device].allSatisfy { $0.count == 0 },
                  "A CPU tick notified an unrelated consumer")

        sample.memory = 75; sample.memoryUsed = 27_000_000_000
        model.applySample(sample)
        try check(memoryGauge.count == 1, "Memory data or warning failed to notify")
        try check(agents.count == 0 && music.count == 0 && settings.count == 0,
                  "Memory tick notified integrations or settings")
        let stableCPU = observe { _ = model.metrics.cpu }
        model.applySample(sample)
        try check(stableCPU.count == 0, "Unchanged CPU reading notified again")

        Bindable(model).prefs.cellSize.wrappedValue = 100
        try check(model.prefs.cellSize == 100 && settings.count == 1,
                  "Nested settings binding no longer updates preferences")
        model.liveAgents = [AgentLiveState(id: "fixture", provider: "Codex", project: "Fixture", state: "running", date: .now)]
        model.spotify = SpotifySnapshot(title: "Fixture", available: true)
        model.appPresence = [AppPresence(id: "fixture", name: "Fixture", running: true)]
        try check(agents.count == 1 && music.count == 1 && apps.count == 1,
                  "Relevant integration changes no longer notify")
        let independentCPU = observe { _ = model.metrics.cpu }
        model.spotify.playing = true
        model.codexAccount.error = "Fixture"
        try check(independentCPU.count == 0, "Integration update notified CPU")

        for key in Model.metricIDs {
            try check(model.metrics.percentage(key) == sample.percentage(key), "Metric conversion changed: \(key)")
        }
        try check(model.history(for: "cpu").last == sample.cpu && model.history(for: "memory").last == sample.memory,
                  "History samples no longer match readings")
        print("Observation checks passed: metric isolation, histories, settings bindings and integration updates")
    }
}
