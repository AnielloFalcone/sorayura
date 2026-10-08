import Foundation

enum AgentPerformanceChecks {
    static func run() async throws {
        func check(_ value: Bool, _ message: String) throws {
            if !value { throw SettingsError.invalid(message) }
        }
        let home = FileManager.default.temporaryDirectory.appending(path: "wallpaper-agent-performance-\(UUID().uuidString)")
        let folder = home.appending(path: ".codex/sessions")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = folder.appending(path: "test.jsonl")
        func token(_ count: Int) -> Data {
            Data("{\"timestamp\":\"2026-10-01T10:00:01Z\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":\(count),\"cached_input_tokens\":\(count / 2),\"output_tokens\":5}}}}\n".utf8)
        }
        func append(_ data: Data) throws {
            let h = try FileHandle(forWritingTo: file); defer { try? h.close() }
            try h.seekToEnd(); try h.write(contentsOf: data)
        }
        let metadata = Data("{\"type\":\"session_meta\",\"payload\":{\"id\":\"test\",\"cwd\":\"/tmp/project\"},\"timestamp\":\"2026-10-01T10:00:00Z\"}\n{\"type\":\"turn_context\",\"payload\":{\"model\":\"test-model\"},\"timestamp\":\"2026-10-01T10:00:00Z\"}\n".utf8)
        // Large irrelevant line followed by valid metadata, exercising skip boundaries.
        try (Data(repeating: 65, count: 1_100_000) + Data("\n".utf8) + metadata + token(100)).write(to: file)
        let reader = AgentUsageReader()
        let first = await reader.scan(home: home, includeExternal: false)
        try check(first.tokens == 100 && first.events.count == 1, "Cold scan skipped token data")
        let cached = await reader.scan(home: home, includeExternal: false)
        try check(cached.tokens == 100 && cached.scannedBytes == 0, "Unchanged log was reread")
        let added = token(160)
        try append(added)
        let delta = await reader.scan(home: home, includeExternal: false)
        try check(delta.tokens == 160 && delta.events.last?.tokens == 60 && delta.scannedBytes == added.count, "Append did not preserve cumulative deltas or reread old data")
        try check(delta.events.last?.model == "test-model" && delta.events.last?.project == "project", "Append lost metadata")
        let partial = token(200)
        try append(partial.prefix(partial.count / 2))
        let incomplete = await reader.scan(home: home, includeExternal: false)
        try check(incomplete.tokens == 160, "Incomplete record was consumed")
        try append(partial.dropFirst(partial.count / 2))
        let complete = await reader.scan(home: home, includeExternal: false)
        try check(complete.tokens == 200 && complete.events.count == 3, "Completed record lost or duplicated")
        await reader.clear()
        let reference = await reader.scan(home: home, includeExternal: false)
        try check(reference.tokens == complete.tokens && reference.cacheFraction == complete.cacheFraction && reference.events.map(\.id) == complete.events.map(\.id), "Incremental results differ from full scan")
        try (metadata + token(50)).write(to: file)
        let truncated = await reader.scan(home: home, includeExternal: false)
        try check(truncated.tokens == 50, "Truncation retained old counters")
        try (metadata + token(80) + Data(repeating: 32, count: 1_000) + Data("\n".utf8)).write(to: file, options: .atomic)
        let replaced = await reader.scan(home: home, includeExternal: false)
        try check(replaced.tokens == 80, "Larger atomic replacement was mistaken for append")
        let preservedDate = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
        try (metadata + token(90) + Data(repeating: 32, count: 1_000) + Data("\n".utf8)).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: preservedDate], ofItemAtPath: file.path)
        let sameSizeReplacement = await reader.scan(home: home, includeExternal: false)
        try check(sameSizeReplacement.tokens == 90, "Same-size replacement with preserved date retained old counters")
        let claudeFolder = home.appending(path: ".claude/projects")
        try FileManager.default.createDirectory(at: claudeFolder, withIntermediateDirectories: true)
        let claudeFile = claudeFolder.appending(path: "test.jsonl")
        func claude(_ count: Int) -> Data {
            Data("{\"type\":\"assistant\",\"cwd\":\"/tmp/claude-project\",\"timestamp\":\"2026-10-01T10:00:00Z\",\"message\":{\"id\":\"same-message\",\"model\":\"claude-test\",\"usage\":{\"input_tokens\":\(count)}}}\n".utf8)
        }
        try claude(20).write(to: claudeFile)
        let initialClaude = await reader.scan(home: home, includeExternal: false)
        try check(initialClaude.tokens == 110, "Claude initial usage incorrect")
        let h = try FileHandle(forWritingTo: claudeFile)
        try h.seekToEnd(); try h.write(contentsOf: claude(30)); try h.close()
        let appendedClaude = await reader.scan(home: home, includeExternal: false)
        try check(appendedClaude.tokens == 120, "Claude append duplicated a message")
        try FileManager.default.removeItem(at: claudeFile)
        try FileManager.default.removeItem(at: file)
        let removed = await reader.scan(home: home, includeExternal: false)
        try check(removed.tokens == 0 && removed.files == 0, "Deleted log retained cached usage")
        print("Agent performance checks passed: bounded lines, unchanged cache, append bytes/deltas, partial lines, full-scan equivalence, truncate, replace, delete")
    }
}
