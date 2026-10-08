import Foundation
import CryptoKit

struct AgentLiveState: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var provider: String
    var project: String
    var state: String
    var date: Date
    var file: String? = nil
    func displayState(now: Date = Date()) -> String {
        if ["running", "waiting"].contains(state) && now.timeIntervalSince(date) > 300 { return "Da verificare" }
        switch state { case "running": return "Al lavoro"; case "waiting": return "In attesa"; case "idle": return "Terminato"; case "ended": return "Sessione chiusa"; default: return "Non disponibile" }
    }
}
enum ClaudeActivity {
    static var folder: URL { ClaudeBridge.folder.deletingLastPathComponent().appending(path: "agent-live") }
    static func decode(_ data: Data, now: Date = Date()) throws -> AgentLiveState {
        guard data.count < 1_000_000, let value = try JSONSerialization.jsonObject(with: data) as? [String: Any], let session = value["session_id"] as? String else { throw SettingsError.invalid("Evento Claude non valido.") }
        let event = value["hook_event_name"] as? String ?? ""
        let state: String
        switch event {
        case "UserPromptSubmit", "PreToolUse", "PostToolUse": state = "running"
        case "PermissionRequest": state = "waiting"
        case "Notification":
            guard ["permission_prompt", "idle_prompt"].contains(value["notification_type"] as? String ?? "") else { throw SettingsError.invalid("Notifica non pertinente.") }
            state = "waiting"
        case "Stop": state = "idle"
        case "SessionEnd": state = "ended"
        default: throw SettingsError.invalid("Evento non supportato.")
        }
        let hash = SHA256.hash(data: Data(session.utf8)).map { String(format: "%02x", $0) }.joined()
        return AgentLiveState(id: "Claude:" + hash, provider: "Claude", project: URL(fileURLWithPath: value["cwd"] as? String ?? "/Sconosciuto").lastPathComponent, state: state, date: now)
    }
    @MainActor static func ingest(_ data: Data) throws {
        guard let stored = try? Data(contentsOf: Model.preferencesURL), let prefs = try? JSONDecoder().decode(Prefs.self, from: stored), prefs.agentUsageEnabled == true else { return }
        let event = try decode(data)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(event).write(to: folder.appending(path: event.id.replacingOccurrences(of: ":", with: "-") + ".json"), options: .atomic)
    }
    static func read() -> [AgentLiveState] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).compactMap {
            guard let data = try? Data(contentsOf: $0), data.count < 20_000 else { return nil }
            return try? JSONDecoder().decode(AgentLiveState.self, from: data)
        }
    }
}
@MainActor enum ClaudeHooksInstaller {
    static let events = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "Stop", "SessionEnd"]
    static func changed(_ object: [String: Any], command: String?) -> [String: Any] {
        var next = object, hooks = object["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups = groups.compactMap { group in
                var group = group
                let entries = (group["hooks"] as? [[String: Any]] ?? []).filter { !(($0["command"] as? String ?? "").contains("--claude-event")) }
                guard !entries.isEmpty else { return nil }
                group["hooks"] = entries; return group
            }
            if let command { groups.append(["hooks":[["type":"command", "command":command, "timeout":3]]]) }
            if groups.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = groups }
        }
        if hooks.isEmpty { next.removeValue(forKey: "hooks") } else { next["hooks"] = hooks }
        return next
    }
    static var installed: Bool {
        guard let object = try? ClaudeBridgeInstaller.current(), let hooks = object["hooks"] as? [String: Any] else { return false }
        return (hooks["UserPromptSubmit"] as? [[String: Any]] ?? []).contains { group in
            (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String ?? "").contains("--claude-event") }
        }
    }
    static func setEnabled(_ enabled: Bool) throws {
        let current = try ClaudeBridgeInstaller.current()
        if let hooks = current["hooks"], !(hooks is [String: Any]) { throw SettingsError.invalid("Formato hook Claude non supportato; nessuna modifica.") }
        if let hooks = current["hooks"] as? [String: Any] {
            for event in events {
                if let value = hooks[event] {
                    guard let groups = value as? [[String: Any]], groups.allSatisfy({ $0["hooks"] is [[String: Any]] }) else { throw SettingsError.invalid(LF("Hook Claude con formato non supportato: \(event). Nessuna modifica.")) }
                }
            }
        }
        let command = enabled ? ClaudeBridgeInstaller.quote(Bundle.main.executablePath!) + " --claude-event" : nil
        let next = changed(current, command: command)
        try FileManager.default.createDirectory(at: ClaudeBridgeInstaller.settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: next, options: [.prettyPrinted, .sortedKeys]).write(to: ClaudeBridgeInstaller.settings, options: .atomic)
    }
}
actor AgentLiveReader {
    private var cached: [URL: AgentLiveState] = [:]
    private var modified: [URL: Date] = [:]
    func seed(_ states: [AgentLiveState]) {
        for state in states {
            guard let file = state.file, Date().timeIntervalSince(state.date) < 86_400 else { continue }
            let url = URL(fileURLWithPath: file)
            if state.date > (cached[url]?.date ?? .distantPast) { cached[url] = state }
        }
    }
    func read() -> [AgentLiveState] { autoreleasepool { readCollected() } }
    private func readCollected() -> [AgentLiveState] {
        let root = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/sessions")
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return ClaudeActivity.read() }
        var seen = Set<URL>()
        for case let file as URL in files {
            guard file.pathExtension == "jsonl", let info = try? file.resourceValues(forKeys: [.contentModificationDateKey]), let date = info.contentModificationDate, Date().timeIntervalSince(date) < 86_400 else { continue }
            seen.insert(file)
            if modified[file] == date { continue }
            modified[file] = date
            guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
            let head = (try? handle.read(upToCount: 65_536)) ?? Data()
            var project = cached[file]?.project ?? "Sconosciuto", internalReview = false
            for line in head.split(separator: 10) {
                if let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any], let payload = object["payload"] as? [String: Any] {
                    if project == "Sconosciuto", let cwd = payload["cwd"] as? String { project = URL(fileURLWithPath: cwd).lastPathComponent }
                    if payload["model"] as? String == "codex-auto-review" { internalReview = true }
                }
            }
            if internalReview { seen.remove(file); continue }
            let length = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: length > 524_288 ? length - 524_288 : 0)
            let tail = (try? handle.readToEnd()) ?? Data()
            let state = Self.parse(tail, id: file.lastPathComponent, project: project, previous: cached[file])
            if let state { cached[file] = state }
        }
        cached = cached.filter { seen.contains($0.key) }
        modified = modified.filter { seen.contains($0.key) }
        return (Array(cached.values) + ClaudeActivity.read()).sorted { $0.date > $1.date }.prefix(20).map { $0 }
    }
    static func parse(_ data: Data, id: String, project: String, previous: AgentLiveState? = nil) -> AgentLiveState? {
        var state = previous
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        for line in data.split(separator: 10) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any], let payload = object["payload"] as? [String: Any], let stamp = object["timestamp"] as? String, let date = formatter.date(from: stamp) ?? fallback.date(from: stamp) else { continue }
            let type = payload["type"] as? String ?? ""
            let next: String?
            switch type { case "task_started": next = "running"; case "task_complete", "task_aborted": next = "idle"; case "approval_requested": next = "waiting"; case "token_count": next = state?.state == "running" ? "running" : nil; default: next = nil }
            if let next, date >= (state?.date ?? .distantPast) { state = AgentLiveState(id: "Codex:" + id, provider: "Codex", project: project, state: next, date: date) }
        }
        return state
    }
}
