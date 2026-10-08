import AppKit
import CryptoKit
import Observation

/// Temporary diagnostics only; never encoded into the user's preferences.
enum PerformanceVariant: String, Codable {
    case full, animationPaused, glassDisabled, widgetsHidden, backgroundOnly
    var pausesAnimation: Bool { self == .animationPaused || self == .backgroundOnly }
    var hidesWidgets: Bool { self == .widgetsHidden || self == .backgroundOnly }
    var disablesGlass: Bool { self == .glassDisabled }
}

@MainActor final class ComponentProfile {
    private struct Phase: Codable {
        let name: String
        let variant: PerformanceVariant
        let started: Date
        var ended: Date?
    }
    private struct Record: Codable {
        let pid: Int32
        let phaseSeconds: Double
        let initialPreferencesSHA256: String
        var state: String
        var reason: String?
        var phases: [Phase]
    }
    private static let variants: [(String, PerformanceVariant)] = [
        ("full-start", .full), ("animation-paused", .animationPaused),
        ("glass-disabled", .glassDisabled), ("widgets-hidden", .widgetsHidden),
        ("background-only", .backgroundOnly), ("full-end", .full)
    ]
    private let model: Model
    private let file: URL
    private var timer: Timer?
    private var record: Record

    init(model: Model, directory: URL, automaticallyAdvance: Bool = true) throws {
        guard !model.editing else { throw SettingsError.invalid("Finish editing before profiling") }
        self.model = model
        file = directory.appendingPathComponent("component-profile.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        record = Record(pid: getpid(), phaseSeconds: 90,
                        initialPreferencesSHA256: try Self.digest(model.prefs), state: "running", phases: [])
        beginNextPhase()
        guard record.state == "running" else { throw SettingsError.invalid("Cannot save diagnostic state") }
        guard automaticallyAdvance else { return }
        let next = Timer(timeInterval: 90, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advance() }
        }
        RunLoop.main.add(next, forMode: .common)
        timer = next
        withObservationTracking { _ = model.prefs } onChange: { [weak self] in
            Task { @MainActor in self?.cancel(reason: "Preferences changed") }
        }
    }

    private static func digest(_ prefs: Prefs) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: try encoder.encode(prefs)).map { String(format: "%02x", $0) }.joined()
    }
    private func beginNextPhase() {
        let phase = Self.variants[record.phases.count]
        record.phases.append(Phase(name: phase.0, variant: phase.1, started: Date()))
        model.performanceVariant = phase.1
        save()
    }
    private func advance() {
        guard record.state == "running" else { return }
        if model.editing { cancel(reason: "Editing started"); return }
        guard (try? Self.digest(model.prefs)) == record.initialPreferencesSHA256 else {
            cancel(reason: "Preferences changed"); return
        }
        record.phases[record.phases.count - 1].ended = Date()
        if record.phases.count == Self.variants.count {
            timer?.invalidate(); timer = nil
            model.performanceVariant = .full
            record.state = "completed"
            save()
        } else { beginNextPhase() }
    }
    func cancel(reason: String) {
        guard record.state == "running" else { return }
        timer?.invalidate(); timer = nil
        model.performanceVariant = .full
        record.phases[record.phases.count - 1].ended = Date()
        record.state = "interrupted"; record.reason = reason
        save()
    }
    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do { try encoder.encode(record).write(to: file, options: .atomic) }
        catch {
            timer?.invalidate(); timer = nil
            model.performanceVariant = .full
            record.state = "interrupted"; record.reason = "Cannot save diagnostic state"
            fputs("Component profile stopped: \(error.localizedDescription)\n", stderr)
        }
    }

    static func checkFixtures() throws {
        func check(_ value: Bool, _ message: String) throws {
            if !value { throw SettingsError.invalid(message) }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("wallpaper-profile-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = Model.isolated()
        let initial = try digest(model.prefs)
        let profile = try ComponentProfile(model: model, directory: directory, automaticallyAdvance: false)
        for variant in variants.dropFirst() {
            profile.advance()
            try check(model.performanceVariant == variant.1, "Component phase failed: \(variant.0)")
        }
        profile.advance()
        try check(profile.record.state == "completed" && model.performanceVariant == .full,
                  "Completed profile did not restore full presentation")
        try check(profile.record.phases.count == 6 && profile.record.phases.allSatisfy { $0.ended != nil },
                  "Missing completed component phase")
        try check(try digest(model.prefs) == initial, "Diagnostic changed user preferences")
        let cancelled = try ComponentProfile(model: model, directory: directory, automaticallyAdvance: false)
        cancelled.advance()
        cancelled.cancel(reason: "Fixture cancellation")
        try check(cancelled.record.state == "interrupted" && model.performanceVariant == .full,
                  "Cancellation did not restore presentation")
        let changed = try ComponentProfile(model: model, directory: directory, automaticallyAdvance: false)
        model.prefs.cellSize += 1
        changed.advance()
        try check(changed.record.state == "interrupted" && model.performanceVariant == .full,
                  "Changed preferences did not cancel the profile")
    }
}
