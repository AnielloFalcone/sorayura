import AppKit
import CryptoKit

struct ClaudeSessionSnapshot: Codable, Sendable {
    var session: String
    var date: Date
    var model: String
    var project: String
    var apiValue: Double?
    var quota: AgentQuota
}

enum ClaudeBridge {
    static var folder: URL { FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/dev.aniello.macsystemwallpaper/claude-status") }
    static func decode(_ data: Data, now: Date = Date()) throws -> ClaudeSessionSnapshot {
        guard data.count < 1_000_000,
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let session = value["session_id"] as? String, !session.isEmpty else { throw SettingsError.invalid("Status line Claude non valida.") }
        let limits = value["rate_limits"] as? [String: Any] ?? [:]
        func limit(_ key: String, minutes: Double) -> AgentLimit? {
            guard let d = limits[key] as? [String: Any], let used = d["used_percentage"] as? NSNumber, let reset = d["resets_at"] as? NSNumber,
                  used.doubleValue.isFinite, reset.doubleValue.isFinite else { return nil }
            return AgentLimit(used: min(100, max(0, used.doubleValue)), reset: Date(timeIntervalSince1970: reset.doubleValue), minutes: minutes)
        }
        let model = value["model"] as? [String: Any] ?? [:]
        let workspace = value["workspace"] as? [String: Any] ?? [:]
        let cost = (value["cost"] as? [String: Any])?["total_cost_usd"] as? NSNumber
        let hash = SHA256.hash(data: Data(session.utf8)).map { String(format: "%02x", $0) }.joined()
        return ClaudeSessionSnapshot(session: hash, date: now, model: model["display_name"] as? String ?? model["id"] as? String ?? "Claude", project: URL(fileURLWithPath: workspace["current_dir"] as? String ?? "/Sconosciuto").lastPathComponent,
            apiValue: cost.flatMap { $0.doubleValue.isFinite && $0.doubleValue >= 0 ? $0.doubleValue : nil },
            quota: AgentQuota(date: now, plan: nil, session: limit("five_hour", minutes: 300), week: limit("seven_day", minutes: 10080)))
    }
    @MainActor static func ingest(_ data: Data) throws {
        // Respect the opt-in even if the status line is still installed after disabling collection.
        guard let stored = try? Data(contentsOf: Model.preferencesURL), let prefs = try? JSONDecoder().decode(Prefs.self, from: stored), prefs.agentUsageEnabled == true else { return }
        let session = try decode(data)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(session).write(to: folder.appending(path: session.session + ".json"), options: .atomic)
    }
    static func sessions() -> [ClaudeSessionSnapshot] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.compactMap { file in
            guard file.pathExtension == "json", let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 20_000,
                  let data = try? Data(contentsOf: file), let session = try? JSONDecoder().decode(ClaudeSessionSnapshot.self, from: data) else { return nil }
            return session
        }
    }
    static func forward(_ data: Data, command: String?, output: FileHandle = .standardOutput) {
        guard let command else { print("Claude · Sorayura"); return }
        let process = Process(), input = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        do {
            try process.run()
            try input.fileHandleForWriting.write(contentsOf: data)
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
        } catch { }
    }
}

@MainActor enum ClaudeBridgeInstaller {
    static var settings: URL { FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/settings.json") }
    static var backup: URL { Model.preferencesURL.deletingLastPathComponent().appending(path: "claude-statusline-backup.json") }
    static func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
    static func current(at settings: URL = settings) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settings.path) else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any] else { throw SettingsError.invalid("Impostazioni Claude non leggibili.") }
        return object
    }
    static var installed: Bool { ((try? current()["statusLine"] as? [String: Any])?["command"] as? String)?.contains("--claude-statusline") == true }
    static func install(settingsURL: URL = settings, backupURL: URL = backup, executableURL: URL? = Bundle.main.executableURL) throws {
        let settings = settingsURL, backup = backupURL
        var object = try current(at: settings)
        if ((object["statusLine"] as? [String: Any])?["command"] as? String)?.contains("--claude-statusline") == true { return }
        let existing = object["statusLine"] as? [String: Any]
        if object["statusLine"] != nil && (existing?["type"] as? String != "command" || existing?["command"] as? String == nil) {
            throw SettingsError.invalid("La status line esistente ha un formato non supportato. Non è stata modificata.")
        }
        guard let executable = executableURL else { throw SettingsError.invalid("Eseguibile non trovato.") }
        var command = quote(executable.path) + " --claude-statusline"
        if let old = existing?["command"] as? String { command += " --forward-statusline " + quote(old) }
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["original": object["statusLine"] ?? NSNull(), "installedCommand": command]).write(to: backup, options: .atomic)
        var line = existing ?? [:]
        line["type"] = "command"; line["command"] = command
        object["statusLine"] = line
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: settings, options: .atomic)
    }
    static func uninstall(settingsURL: URL = settings, backupURL: URL = backup) throws {
        let settings = settingsURL, backup = backupURL
        var object = try current(at: settings)
        guard let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: backup)) as? [String: Any],
              let command = (object["statusLine"] as? [String: Any])?["command"] as? String,
              command == saved["installedCommand"] as? String else { throw SettingsError.invalid("La status line è stata modificata dopo il collegamento. Ripristino automatico annullato.") }
        if saved["original"] is NSNull { object.removeValue(forKey: "statusLine") }
        else { object["statusLine"] = saved["original"] }
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: settings, options: .atomic)
    }
}
