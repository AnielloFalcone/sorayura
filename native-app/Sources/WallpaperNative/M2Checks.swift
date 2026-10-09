import Foundation

@MainActor enum M2Checks {
    static func run() throws {
        func check(_ passed: Bool, _ message: String) throws {
            if !passed { throw SettingsError.invalid(message) }
        }
        let codex = """
        {"type":"session_meta","payload":{"id":"session","cwd":"/tmp/project"},"timestamp":"2026-10-01T10:00:00Z"}
        {"type":"turn_context","payload":{"model":"example-model"},"timestamp":"2026-10-01T10:00:00Z"}
        {"timestamp":"2026-10-01T10:00:01.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100,"cached_input_tokens":20,"output_tokens":10}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":30,"resets_at":1790900000,"window_minutes":300}}}}
        {"timestamp":"2026-10-01T10:00:02Z","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100,"cached_input_tokens":20,"output_tokens":10}}}}
        broken-json
        {"timestamp":"2026-10-01T10:00:03Z","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":160,"cached_input_tokens":50,"output_tokens":15}}}}
        """
        let result = AgentUsageReader.parse(Data(codex.utf8), provider: "Codex", source: "fixture")
        try check(result.events.count == 2 && result.tokens == 160, "Repeated cumulative token events were counted twice")
        try check(result.events.reduce(0) { $0 + $1.cached } == 50, "Cached token deltas incorrect")
        try check(result.events.last?.project == "project" && result.events.last?.model == "example-model", "Metadata lost")
        try check(result.codexQuota?.session?.used == 30, "Quota missing")
        let temporary = FileManager.default.temporaryDirectory.appending(path: "wallpaper-m2-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try (Data(repeating: 65, count: 1_100_000) + Data("\n".utf8) + Data(codex.utf8)).write(to: temporary)
        let streamed = AgentUsageReader.parseLines(try UsageLines(temporary), provider: "Codex", source: "fixture")
        try check(streamed.tokens == result.tokens && streamed.events.count == result.events.count, "Streaming lost usage after oversized lines")
        let claude = """
        {"type":"assistant","cwd":"/tmp/work","timestamp":"2026-10-01T10:00:01Z","message":{"id":"message","model":"example-claude","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":20,"cache_creation_input_tokens":30}}}
        """
        let usage = AgentUsageReader.parse(Data(claude.utf8), provider: "Claude", source: "fixture")
        try check(usage.tokens == 65 && usage.events.first?.cached == 20, "Claude cache accounting incorrect")
        try check(AgentUsageReader.deduplicate(usage.events + usage.events).count == 1, "Claude duplicated message counted twice")
        try check(usage.codexQuota == nil, "Claude quota fabricated")
        try check(ThermalPresentation.frames(.critical, lowPower: false, adaptive: true) == 10, "Critical energy policy incorrect")
        try check(ThermalPresentation.frames(.nominal, lowPower: true, adaptive: true) == 20, "Low power energy policy incorrect")
        try check(ThermalPresentation.frames(.serious, lowPower: true, adaptive: false) == 30, "Energy override ignored")
        let bridgeInput = Data("{\"session_id\":\"sample\",\"model\":{\"display_name\":\"Claude\"},\"workspace\":{\"current_dir\":\"/tmp/project\"},\"cost\":{\"total_cost_usd\":1.25},\"rate_limits\":{\"five_hour\":{\"used_percentage\":23.5,\"resets_at\":1790900000}}}".utf8)
        let bridge = try ClaudeBridge.decode(bridgeInput)
        try check(bridge.apiValue == 1.25 && bridge.quota.session?.used == 23.5 && bridge.quota.week == nil, "Claude statusline counters incorrect")
        try check(bridge.session != "sample" && bridge.session.count == 64, "Session identifier not anonymized")
        let roundtrip = try JSONDecoder().decode(ClaudeSessionSnapshot.self, from: JSONEncoder().encode(bridge))
        try check(roundtrip.project == "project", "Claude snapshot persistence incorrect")
        let testFolder = FileManager.default.temporaryDirectory.appending(path: "wallpaper-claude-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testFolder) }
        let watchedFolder = testFolder.appending(path: ".codex/sessions")
        try FileManager.default.createDirectory(at: watchedFolder, withIntermediateDirectories: true)
        let watcher = AgentFileWatcher()
        var notifications = 0
        watcher.start(home: testFolder) { notifications += 1 }
        let watchedFile = watchedFolder.appending(path: "new-session.jsonl")
        try Data("first\n".utf8).write(to: watchedFile)
        let deadline = Date().addingTimeInterval(5)
        while notifications == 0 && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        try check(notifications > 0, "Native watcher missed a newly created session")
        notifications = 0
        try Data("second\n".utf8).write(to: watchedFile, options: .atomic)
        let secondDeadline = Date().addingTimeInterval(5)
        while notifications == 0 && Date() < secondDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        try check(notifications > 0, "Native watcher missed atomic replacement")
        watcher.stop()
        let testSettings = testFolder.appending(path: "settings.json"), testBackup = testFolder.appending(path: "backup.json")
        let initial: [String: Any] = ["theme":"dark", "statusLine":["type":"command", "command":"cat", "padding":2]]
        try JSONSerialization.data(withJSONObject: initial).write(to: testSettings)
        try ClaudeBridgeInstaller.install(settingsURL: testSettings, backupURL: testBackup, executableURL: URL(fileURLWithPath: "/tmp/an app's path"))
        var modified = try ClaudeBridgeInstaller.current(at: testSettings)
        let legacy = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Developer/macbook-system-wallpaper-m0/native-app/build/Mac System Wallpaper.app/Contents/MacOS/MacSystemWallpaper")
        let renamed = URL(fileURLWithPath: "/Applications/Sorayura.app/Contents/MacOS/Sorayura")
        try ClaudeBridgeInstaller.uninstall(settingsURL: testSettings, backupURL: testBackup)
        try ClaudeBridgeInstaller.install(settingsURL: testSettings, backupURL: testBackup, executableURL: legacy)
        modified = ClaudeHooksInstaller.changed(try ClaudeBridgeInstaller.current(at: testSettings), command: ClaudeBridgeInstaller.quote(legacy.path) + " --claude-event")
        try JSONSerialization.data(withJSONObject: modified).write(to: testSettings)
        try BrandMigration.relocate(settingsURL: testSettings, backupURL: testBackup, executableURL: renamed)
        let relocated = try ClaudeBridgeInstaller.current(at: testSettings)
        try check((relocated["statusLine"] as? [String: Any])?["command"] as? String == ClaudeBridgeInstaller.quote(renamed.path) + " --claude-statusline --forward-statusline 'cat'", "Brand migration loses forwarded status line")
        let encodedRelocated = try JSONSerialization.data(withJSONObject: relocated, options: .sortedKeys)
        try check(!String(decoding: encodedRelocated, as: UTF8.self).contains("MacSystemWallpaper"), "Brand migration leaves legacy hook paths")
        try BrandMigration.relocate(settingsURL: testSettings, backupURL: testBackup, executableURL: renamed)
        try check(try JSONSerialization.data(withJSONObject: ClaudeBridgeInstaller.current(at: testSettings), options: .sortedKeys) == encodedRelocated, "Brand migration is not idempotent")
        modified = ClaudeHooksInstaller.changed(relocated, command: nil)
        modified["theme"] = "light"
        try JSONSerialization.data(withJSONObject: modified).write(to: testSettings)
        try ClaudeBridgeInstaller.uninstall(settingsURL: testSettings, backupURL: testBackup)
        let restoredLine = try ClaudeBridgeInstaller.current(at: testSettings)
        try check(restoredLine["theme"] as? String == "light" && NSDictionary(dictionary: restoredLine["statusLine"] as! [String: Any]).isEqual(to: initial["statusLine"] as! [String: Any]), "Statusline restore loses unrelated settings")
        let forwarded = testFolder.appending(path: "forward.json")
        FileManager.default.createFile(atPath: forwarded.path, contents: nil)
        let writer = try FileHandle(forWritingTo: forwarded)
        ClaudeBridge.forward(bridgeInput, command: "cat", output: writer)
        try writer.close()
        try check((try Data(contentsOf: forwarded)) == bridgeInput, "Existing statusline stdin not preserved")
        let now = Date()
        let desktopFixture = try JSONSerialization.data(withJSONObject: ["version":2, "samples":[["t":now.timeIntervalSince1970 * 1000, "u":["fh":25,"sd":62,"so":40,"sn":17]]]])
        let desktop = ClaudeDesktopLimits.decode(desktopFixture, now: now)
        try check(desktop?.quota.session?.used == 25 && desktop?.quota.week?.used == 62 && desktop?.opus?.used == 40 && desktop?.quota.session?.reset == nil, "Desktop Claude limits or unknown reset incorrect")
        try check(ClaudeDesktopLimits.decode(desktopFixture, now: now.addingTimeInterval(301 * 60))?.quota.session == nil, "Expired desktop session remains visible")
        try check(ClaudeDesktopLimits.decode(Data("{\"version\":99,\"samples\":[]}".utf8)) == nil, "Unknown desktop schema accepted")
        let running = try ClaudeActivity.decode(Data("{\"session_id\":\"sample\",\"cwd\":\"/tmp/work\",\"hook_event_name\":\"UserPromptSubmit\"}".utf8), now: now)
        try check(running.displayState(now: now) == "Al lavoro" && running.displayState(now: now.addingTimeInterval(301)) == "Da verificare", "Stale live state remains running")
        let waiting = try ClaudeActivity.decode(Data("{\"session_id\":\"sample\",\"hook_event_name\":\"PermissionRequest\"}".utf8))
        try check(waiting.state == "waiting", "Permission request not tracked")
        let original: [String: Any] = ["theme":"dark", "hooks":["Stop":[["matcher":"", "hooks":[["type":"command", "command":"echo original"]]]]]]
        let installed = ClaudeHooksInstaller.changed(original, command: "wallpaper --claude-event")
        let reinstalled = ClaudeHooksInstaller.changed(installed, command: "wallpaper --claude-event")
        let restored = ClaudeHooksInstaller.changed(reinstalled, command: nil)
        try check(NSDictionary(dictionary: restored).isEqual(to: original), "Hook installation loses existing settings or duplicates hooks")
        let started = "{\"timestamp\":\"2026-10-01T10:00:00Z\",\"payload\":{\"type\":\"task_started\"}}"
        let stopped = "{\"timestamp\":\"2026-10-01T10:00:01Z\",\"payload\":{\"type\":\"task_complete\"}}"
        let active = AgentLiveReader.parse(Data(started.utf8), id: "test", project: "work")
        let seeded = AgentUsageReader.parse(Data((started + "\n" + codex).utf8), provider: "Codex", source: "/tmp/test.jsonl").codexActivity.first
        try check(seeded?.state == "running" && seeded?.file == "/tmp/test.jsonl", "Full history does not seed long-running tasks")
        let heartbeat = "{\"timestamp\":\"2026-10-01T10:00:05Z\",\"payload\":{\"type\":\"token_count\"}}"
        try check(AgentLiveReader.parse(Data(heartbeat.utf8), id: "test", project: "work", previous: seeded)?.state == "running", "Tail heartbeat loses seeded task status")
        try check(active?.state == "running", "Codex start ignored")
        try check(AgentLiveReader.parse(Data(stopped.utf8), id: "test", project: "work", previous: active)?.state == "idle", "Codex completion ignored")
        let account: [String: Any] = ["rateLimitsByLimitId":["codex":["primary":["usedPercent":44, "resetsAt":1790900000, "windowDurationMins":300]]]]
        try check(CodexAccountReader.quota(account)?.session?.used == 44, "Official account quota schema ignored")
        let validQuota = AgentQuota(date: now, plan: nil, session: AgentLimit(used: 20, reset: now.addingTimeInterval(60), minutes: 300), week: nil)
        let expiredQuota = AgentQuota(date: now, plan: nil, session: AgentLimit(used: 20, reset: now.addingTimeInterval(-1), minutes: 300), week: nil)
        try check(CodexAccountReader.refreshInterval(quota: validQuota, now: now) == 300 && CodexAccountReader.refreshInterval(quota: expiredQuota, now: now) == 60 && CodexAccountReader.refreshInterval(quota: nil, now: now) == 60, "Expired or missing account limits do not refresh promptly")
        let ai = BuiltInPreset.all.first { $0.id == "ai" }!.settings(from: Prefs(), displayKeys: ["laptop", "external"], displaySizes: ["laptop": NSSize(width: 1440, height: 900), "external": NSSize(width: 2560, height: 1440)])
        try ai.validate()
        try check(ai.agentUsageEnabled != true && ai.spotifyEnabled != true && ai.codexAccountEnabled != true, "Preset enables network or permissions unexpectedly")
        for point in ai.positions["laptop"]!.values { try check(point.y < 90, "AI preset overflows laptop") }
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Prefs())) as! [String: Any]
        json.removeValue(forKey: "agentUsageEnabled"); json.removeValue(forKey: "appStatusEnabled"); json.removeValue(forKey: "adaptiveAnimation")
        let old = try JSONDecoder().decode(Prefs.self, from: JSONSerialization.data(withJSONObject: json))
        try check(old.agentUsageEnabled != true && old.appStatusEnabled != true, "Existing settings enable integrations unexpectedly")
        try old.validate()
        print("M2 checks passed: token deltas, cache, quota, malformed records, thermal policy, old settings")
    }
}
