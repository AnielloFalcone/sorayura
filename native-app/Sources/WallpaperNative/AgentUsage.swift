import Foundation
import Darwin

struct AgentUsageEvent: Sendable {
    let id: String
    let provider: String
    let date: Date
    let model: String
    let project: String
    let tokens: Double
    let cached: Double
    let output: Double
}
struct AgentLimit: Codable, Sendable {
    let used: Double
    let reset: Date?
    let minutes: Double
}
struct AgentQuota: Codable, Sendable {
    let date: Date
    let plan: String?
    let session: AgentLimit?
    let week: AgentLimit?
}
struct AgentPeriodSummary: Sendable {
    var tokens = 0.0
    var cached = 0.0
    var models: [(String, Double)] = []
    var projects: [(String, Double)] = []
    var days: [Date: Double] = [:]
    var claudeDays: [Date: Double] = [:]
    var codexDays: [Date: Double] = [:]
}
struct AgentUsageSnapshot: Sendable {
    var periods: [String: AgentPeriodSummary] = [:]
    var codexActivity: [AgentLiveState] = []
    var events: [AgentUsageEvent] = []
    var codexQuota: AgentQuota?
    var claudeSessions: [ClaudeSessionSnapshot] = []
    var claudeDesktop: ClaudeDesktopLimits?
    var updated: Date?
    var skipped = 0
    var files = 0
    var scannedBytes = 0
    var parsedFiles = 0
    var modelTotals: [(String, Double)] = []
    var projectTotals: [(String, Double)] = []
    var dayTotals: [Date: Double] = [:]
    var hourlyClaude = Array(repeating: 0.0, count: 24)
    var hourlyCodex = Array(repeating: 0.0, count: 24)
    var todayTokens = 0.0
    var summaryTokens: Double?
    var summaryCached: Double?
    var tokens: Double { summaryTokens ?? events.reduce(0) { $0 + $1.tokens } }
    var cacheFraction: Double { tokens > 0 ? (summaryCached ?? events.reduce(0) { $0 + $1.cached }) / tokens : 0 }
    func today(_ now: Date = Date()) -> [AgentUsageEvent] { events.filter { Calendar.current.isDate($0.date, inSameDayAs: now) } }
    func grouped(_ key: KeyPath<AgentUsageEvent, String>) -> [(String, Double)] {
        if key == \AgentUsageEvent.model { return modelTotals }
        if key == \AgentUsageEvent.project { return projectTotals }
        return Dictionary(grouping: events, by: { $0[keyPath: key] }).map { ($0.key, $0.value.reduce(0) { $0 + $1.tokens }) }.sorted { $0.1 > $1.1 }
    }
}

// Only derived usage metadata is retained; prompts, responses and auth files are never retained.
actor AgentUsageReader {
    private struct ParseState {
        var result = AgentUsageSnapshot()
        var project = "Sconosciuto", model = "Sconosciuto", session: String
        var liveState: AgentLiveState?
        var previous = 0.0, previousCached = 0.0, previousOutput = 0.0
    }
    private struct CachedFile {
        var size: Int
        var modified: Date
        var identity: NSObject?
        var offset: UInt64
        var anchor: Data
        var head: Data
        var state: ParseState
    }
    private var cache: [URL: CachedFile] = [:]
    func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser, includeExternal: Bool = true) -> AgentUsageSnapshot {
        autoreleasepool { scanCollected(home: home, includeExternal: includeExternal) }
    }
    private func scanCollected(home: URL, includeExternal: Bool) -> AgentUsageSnapshot {
        var combined = AgentUsageSnapshot()
        var present = Set<URL>()
        for (provider, folder) in [("Codex", ".codex/sessions"), ("Claude", ".claude/projects")] {
            let root = home.appending(path: folder)
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey, .fileResourceIdentifierKey], options: [.skipsHiddenFiles]) else { continue }
            for case let file as URL in enumerator where file.pathExtension == "jsonl" {
                present.insert(file)
                guard let info = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey, .fileResourceIdentifierKey]), info.isSymbolicLink != true,
                      let size = info.fileSize, let modified = info.contentModificationDate else { combined.skipped += 1; continue }
                let result: AgentUsageSnapshot
                if let old = cache[file], old.size == size && old.modified == modified && old.identity == (info.fileResourceIdentifier as? NSObject) { result = old.state.result }
                else {
                    // Logs are append-only. Validate identity and both ends before reusing
                    // cumulative counters; replacements/truncations restart from zero.
                    guard let handle = try? FileHandle(forReadingFrom: file) else { combined.skipped += 1; continue }
                    defer { try? handle.close() }
                    let identity = info.fileResourceIdentifier as? NSObject
                    var old = cache.removeValue(forKey: file)
                    let append = old.map { entry in
                        size > entry.size && identity != nil && entry.identity == identity &&
                        Self.bytes(handle, offset: 0, count: entry.head.count) == entry.head &&
                        Self.bytes(handle, offset: entry.offset - UInt64(entry.anchor.count), count: entry.anchor.count) == entry.anchor
                    } ?? false
                    if !append { old = nil }
                    var entry = old ?? CachedFile(size: size, modified: modified, identity: identity,
                        offset: 0, anchor: Data(), head: Data(), state: ParseState(session: file.path))
                    guard let lines = try? UsageLines(file, offset: entry.offset, limit: UInt64(size), includeFinalLine: false) else { combined.skipped += 1; continue }
                    Self.consume(lines, provider: provider, source: file.path, state: &entry.state)
                    combined.scannedBytes += Int(lines.bytesRead)
                    combined.parsedFiles += 1
                    entry.size = size; entry.modified = modified; entry.identity = identity
                    entry.offset = lines.completeOffset
                    let anchorCount = Int(min(256, entry.offset))
                    entry.anchor = Self.bytes(handle, offset: entry.offset - UInt64(anchorCount), count: anchorCount)
                    entry.head = Self.bytes(handle, offset: 0, count: min(256, Int(entry.offset)))
                    result = entry.state.result
                    cache[file] = entry
                }
                combined.files += 1
                combined.events += result.events
                combined.codexActivity += result.codexActivity
                if let quota = result.codexQuota, quota.date > (combined.codexQuota?.date ?? .distantPast) { combined.codexQuota = quota }
            }
        }
        cache = cache.filter { present.contains($0.key) }
        // Claude can store the same assistant message in several transcript branches.
        combined.events = Self.deduplicate(combined.events)
        var models: [String: Double] = [:], projects: [String: Double] = [:]
        let calendar = Calendar.current, now = Date()
        var total = 0.0, cached = 0.0
        let today = calendar.startOfDay(for: now)
        var eventDays: [Date] = []
        eventDays.reserveCapacity(combined.events.count)
        var dayInterval: DateInterval?
        for event in combined.events {
            total += event.tokens; cached += event.cached
            models[event.model, default: 0] += event.tokens
            projects[event.project, default: 0] += event.tokens
            // Sorted events share one calendar calculation for each day, including DST.
            if dayInterval == nil || event.date < dayInterval!.start || event.date >= dayInterval!.end {
                dayInterval = calendar.dateInterval(of: .day, for: event.date)
            }
            let day = dayInterval?.start ?? calendar.startOfDay(for: event.date)
            eventDays.append(day)
            combined.dayTotals[day, default: 0] += event.tokens
            if day == today {
                combined.todayTokens += event.tokens
                let hour = calendar.component(.hour, from: event.date)
                if event.provider == "Claude" { combined.hourlyClaude[hour] += event.tokens }
                else { combined.hourlyCodex[hour] += event.tokens }
            }
        }
        for period in ["today", "week", "month", "all"] {
            let days = period == "today" ? 1 : period == "week" ? 7 : period == "month" ? 30 : 0
            let start = days == 0 ? Date.distantPast : calendar.date(byAdding: .day, value: 1 - days, to: today)!
            var summary = AgentPeriodSummary(), periodModels: [String: Double] = [:], periodProjects: [String: Double] = [:]
            for (index, event) in combined.events.enumerated() where event.date >= start && event.date <= now {
                summary.tokens += event.tokens; summary.cached += event.cached
                let day = eventDays[index]
                summary.days[day, default: 0] += event.tokens
                if event.provider == "Claude" { summary.claudeDays[day, default: 0] += event.tokens }
                else { summary.codexDays[day, default: 0] += event.tokens }
                periodModels[event.model, default: 0] += event.tokens
                periodProjects[event.project, default: 0] += event.tokens
            }
            summary.models = periodModels.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
            summary.projects = periodProjects.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
            combined.periods[period] = summary
        }
        combined.summaryTokens = total; combined.summaryCached = cached
        combined.modelTotals = models.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
        combined.projectTotals = projects.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
        if includeExternal {
            combined.claudeSessions = ClaudeBridge.sessions()
            combined.claudeDesktop = ClaudeDesktopLimits.read()
        }
        combined.updated = Date()
        return combined
    }
    static func deduplicate(_ events: [AgentUsageEvent]) -> [AgentUsageEvent] {
        var unique: [String: AgentUsageEvent] = [:]
        for event in events {
            if let old = unique[event.id], old.tokens > event.tokens { continue }
            unique[event.id] = event
        }
        return unique.values.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
    func clear() { cache.removeAll() }
    static func parse(_ data: Data, provider: String, source: String) -> AgentUsageSnapshot {
        parseLines(data.split(separator: 10).lazy.map { Data($0) }, provider: provider, source: source)
    }
    private static func bytes(_ handle: FileHandle, offset: UInt64, count: Int) -> Data {
        guard count > 0 else { return Data() }
        try? handle.seek(toOffset: offset)
        return (try? handle.read(upToCount: count)) ?? Data()
    }
    static func parseLines<S: Sequence>(_ lines: S, provider: String, source: String) -> AgentUsageSnapshot where S.Element == Data {
        var state = ParseState(session: source)
        consume(lines, provider: provider, source: source, state: &state)
        return state.result
    }
    private static func consume<S: Sequence>(_ lines: S, provider: String, source: String, state: inout ParseState) where S.Element == Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        func number(_ object: [String: Any], _ key: String) -> Double { max(0, (object[key] as? NSNumber)?.doubleValue ?? 0) }
        func limit(_ object: Any?) -> AgentLimit? {
            guard let d = object as? [String: Any], let used = d["used_percent"] as? NSNumber, let reset = d["resets_at"] as? NSNumber else { return nil }
            return AgentLimit(used: min(100, max(0, used.doubleValue)), reset: Date(timeIntervalSince1970: reset.doubleValue), minutes: number(d, "window_minutes"))
        }
        for line in lines {
            autoreleasepool {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { return }
                let payload = object["payload"] as? [String: Any] ?? [:]
                if let cwd = (provider == "Codex" ? payload["cwd"] : object["cwd"]) as? String { state.project = URL(fileURLWithPath: cwd).lastPathComponent }
                if object["type"] as? String == "session_meta", let id = payload["id"] as? String { state.session = id }
                if let value = payload["model"] as? String { state.model = value }
                guard let stamp = object["timestamp"] as? String, let date = formatter.date(from: stamp) ?? fallback.date(from: stamp) else { return }
                if provider == "Codex" {
                    let type = payload["type"] as? String ?? ""
                    let next: String?
                    switch type {
                    case "task_started": next = "running"
                    case "task_complete", "task_aborted": next = "idle"
                    case "approval_requested": next = "waiting"
                    case "token_count": next = state.liveState?.state == "running" ? "running" : nil
                    default: next = nil
                    }
                    if let next { state.liveState = AgentLiveState(id: "Codex:" + URL(fileURLWithPath: source).lastPathComponent, provider: provider, project: state.project, state: next, date: date, file: source) }
                }
                if provider == "Codex", payload["type"] as? String == "token_count" {
                    if let quotas = payload["rate_limits"] as? [String: Any], (quotas["limit_id"] as? String ?? "codex") == "codex" {
                        state.result.codexQuota = AgentQuota(date: date, plan: quotas["plan_type"] as? String, session: limit(quotas["primary"]), week: limit(quotas["secondary"]))
                    }
                    guard let info = payload["info"] as? [String: Any], let usage = info["total_token_usage"] as? [String: Any] else { return }
                    let total = number(usage, "total_tokens"), cached = number(usage, "cached_input_tokens"), output = number(usage, "output_tokens")
                    // Cumulative counters: repeated events must not count the same request twice.
                    let delta = max(0, total - state.previous)
                    if delta > 0 && state.model != "codex-auto-review" {
                        state.result.events.append(AgentUsageEvent(id: "Codex:\(state.session):\(Int(total))", provider: provider, date: date, model: state.model, project: state.project, tokens: delta, cached: min(delta, max(0, cached - state.previousCached)), output: min(delta, max(0, output - state.previousOutput))))
                    }
                    state.previous = max(state.previous, total); state.previousCached = max(state.previousCached, cached); state.previousOutput = max(state.previousOutput, output)
                } else if provider == "Claude", object["type"] as? String == "assistant",
                          let message = object["message"] as? [String: Any], let usage = message["usage"] as? [String: Any], let id = message["id"] as? String {
                    let cached = number(usage, "cache_read_input_tokens"), output = number(usage, "output_tokens")
                    let total = number(usage, "input_tokens") + number(usage, "cache_creation_input_tokens") + cached + output
                    state.result.events.append(AgentUsageEvent(id: "Claude:\(id)", provider: provider, date: date, model: message["model"] as? String ?? state.model, project: state.project, tokens: total, cached: cached, output: output))
                }
            }
        }
        if let live = state.liveState, state.model != "codex-auto-review" { state.result.codexActivity = [live] }
    }
}
func tokenLabel(_ value: Double) -> String {
    if value >= 1_000_000_000 { return String(format: "%.1fB", value / 1_000_000_000) }
    if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
    return String(format: "%.0f", value)
}

// Stream transcripts in bounded chunks, including very large files. Oversized message
// bodies are skipped; usage metadata lines are normally only a few kilobytes.
final class UsageLines: Sequence, IteratorProtocol {
    private let handle: FileHandle
    private var buffer = Data()
    private var cursor = 0
    private var pending = Data()
    private var eof = false
    private var discarding = false
    private let initialOffset: UInt64
    var bytesRead: UInt64 { readOffset - initialOffset }
    private let limit: UInt64
    private var readOffset: UInt64
    private(set) var completeOffset: UInt64
    private let includeFinalLine: Bool
    init(_ file: URL, offset: UInt64 = 0, limit: UInt64 = .max, includeFinalLine: Bool = true) throws {
        handle = try FileHandle(forReadingFrom: file)
        try handle.seek(toOffset: offset)
        self.limit = limit; initialOffset = offset; readOffset = offset; completeOffset = offset
        self.includeFinalLine = includeFinalLine
    }
    deinit { try? handle.close() }
    func makeIterator() -> UsageLines { self }
    func next() -> Data? { autoreleasepool { nextCollected() } }
    private func nextCollected() -> Data? {
        while true {
            if cursor < buffer.count {
                let newline: Int? = buffer.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress,
                          let found = memchr(base.advanced(by: cursor), 10, raw.count - cursor) else { return nil }
                    return base.distance(to: found)
                }
                let end = newline ?? buffer.count
                if !discarding {
                    if pending.count + end - cursor > 1_000_000 { pending = Data(); discarding = true }
                    else { pending.append(buffer[cursor..<end]) }
                }
                cursor = end + (newline == nil ? 0 : 1)
                if newline != nil {
                    completeOffset = readOffset - UInt64(buffer.count - cursor)
                    let line = discarding ? Data() : pending
                    pending = Data(); discarding = false
                    return line
                }
            }
            if eof {
                guard includeFinalLine, !pending.isEmpty else { return nil }
                let line = pending; pending = Data()
                return line
            }
            let count = Swift.min(UInt64(65_536), limit - Swift.min(limit, readOffset))
            guard count > 0, let chunk = try? handle.read(upToCount: Int(count)), !chunk.isEmpty else { eof = true; continue }
            buffer = chunk; cursor = 0; readOffset += UInt64(chunk.count)
        }
    }
}
