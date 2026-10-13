import Foundation
import Darwin

struct ClaudeAccountSnapshot: Sendable {
    var quota: AgentQuota?
    var error: String?
}

/// Uses the authenticated first-party client. No tokens, private HTTP endpoints,
/// model prompts, hooks or project customizations are accessed by Sorayura.
actor ClaudeAccountReader {
    static var executable: String? {
        ["/opt/homebrew/bin/claude", "/usr/local/bin/claude", FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin/claude").path].first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    func read() -> ClaudeAccountSnapshot {
        guard let executable = Self.executable else { return .init(error: "Claude Code non installato.") }
        var master: Int32 = -1, slave: Int32 = -1
        var size = winsize(ws_row: 80, ws_col: 160, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &size) == 0 else { return .init(error: "Lettura Claude Code non riuscita.") }
        let terminal = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--safe-mode"]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"; env["IS_DEMO"] = "1"
        env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        // Finder-launched apps may omit USER; Claude uses it to locate its Keychain login.
        env["USER"] = NSUserName()
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["LANG"] = "en_US.UTF-8"
        process.environment = env
        process.standardInput = terminal; process.standardOutput = terminal; process.standardError = terminal
        defer {
            // Only this diagnostic child is stopped, never an existing Claude session.
            if process.isRunning {
                process.terminate()
                let end = Date().addingTimeInterval(1)
                while process.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.02) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
            }
            close(master); close(slave)
        }
        do { try process.run() } catch { return .init(error: "Lettura Claude Code non riuscita.") }
        _ = fcntl(master, F_SETFL, O_NONBLOCK)
        var bytes = Data(), sent = false
        var promptSeen: Date?
        let deadline = Date().addingTimeInterval(20)
        while process.isRunning && Date() < deadline {
            var buffer = [UInt8](repeating: 0, count: 16384)
            let count = Darwin.read(master, &buffer, buffer.count)
            if count > 0 { bytes.append(contentsOf: buffer.prefix(count)) }
            if bytes.count > 524288 { break }
            let screen = UsageTerminal.render(String(decoding: bytes, as: UTF8.self))
            if promptSeen == nil && screen.contains("❯") { promptSeen = Date() }
            // The initial prompt is drawn before the CLI finishes registering
            // input handlers; sending immediately can lose the slash command.
            if !sent, let promptSeen, Date().timeIntervalSince(promptSeen) >= 2 {
                let command = Array("/usage\r".utf8)
                _ = command.withUnsafeBytes { Darwin.write(master, $0.baseAddress, $0.count) }
                sent = true
            }
            if sent, let quota = Self.parse(screen) { return .init(quota: quota) }
            if screen.contains("Not logged in") || screen.contains("Please log in") {
                return .init(error: "Claude Code richiede il login.")
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let screen = UsageTerminal.render(String(decoding: bytes, as: UTF8.self))
        // Diagnostics expose only control flow, never terminal content or identifiers.
        let flags: [String: Bool] = ["sentUsage": sent, "sessionHeading": screen.contains("Current session"), "weekHeading": screen.contains("Current week"), "commandVisible": screen.contains("/usage"), "usageTab": screen.contains("Usage"), "loading": screen.contains("Loading"), "hasReset": screen.contains("Resets"), "loginRequired": screen.lowercased().contains("log in"), "trustPrompt": screen.contains("trust"), "childRunning": process.isRunning]
        if let data = try? JSONSerialization.data(withJSONObject: flags) {
            let path = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/dev.aniello.macsystemwallpaper/claude-reader-diagnostic.json")
            try? data.write(to: path, options: .atomic)
        }
        return .init(error: "Claude Code non ha restituito i limiti. Riproveremo automaticamente.")
    }
    static func parse(_ screen: String, now: Date = Date()) -> AgentQuota? {
        func limit(_ heading: String, minutes: Double) -> AgentLimit? {
            guard let start = screen.range(of: heading) else { return nil }
            let tail = String(screen[start.upperBound...].prefix(600))
            let block = String(tail.prefix(upTo: tail.range(of: "Current ")?.lowerBound ?? tail.endIndex))
            guard let used = block.range(of: #"\b([0-9]{1,3}(?:\.[0-9]+)?)%\s+used"#, options: .regularExpression),
                  let percentage = Double(block[used].split(separator: "%")[0]), (0...100).contains(percentage),
                  let resetRange = block.range(of: #"Resets[^\n]+"#, options: .regularExpression) else { return nil }
            let reset = parseReset(String(block[resetRange]), now: now, weekly: minutes > 300)
            guard let reset else { return nil }
            return AgentLimit(used: percentage, reset: reset, minutes: minutes)
        }
        guard let session = limit("Current session", minutes: 300), let week = limit("Current week (all models)", minutes: 10080) else { return nil }
        return AgentQuota(date: now, plan: nil, session: session, week: week)
    }
    static func parseReset(_ raw: String, now: Date, weekly: Bool) -> Date? {
        guard let open = raw.lastIndex(of: "("), let close = raw.lastIndex(of: ")"), open < close,
              let zone = TimeZone(identifier: String(raw[raw.index(after: open)..<close])) else { return nil }
        let text = raw[..<open].replacingOccurrences(of: "Resets", with: "").trimmingCharacters(in: .whitespaces)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = zone; formatter.isLenient = false
        if weekly {
            for format in ["MMM d 'at' ha yyyy", "MMM d 'at' h:mma yyyy"] {
                formatter.dateFormat = format
                let year = calendar.component(.year, from: now)
                if let date = formatter.date(from: text + " \(year)"), date > now, date.timeIntervalSince(now) <= 8 * 86400 { return date }
                if let date = formatter.date(from: text + " \(year + 1)"), date > now, date.timeIntervalSince(now) <= 8 * 86400 { return date }
            }
        } else {
            for format in ["h:mma", "ha"] {
                formatter.dateFormat = format
                if let time = formatter.date(from: text) {
                    let parts = calendar.dateComponents([.hour, .minute], from: time)
                    if let date = calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime), date.timeIntervalSince(now) <= 5 * 3600 { return date }
                }
            }
        }
        return nil
    }
}

/// Reconstruct a bounded terminal screen; cursor updates must not turn fragments
/// from different redraws into a fabricated quota reading. Raw output is not saved.
private enum UsageTerminal {
    static func render(_ raw: String) -> String {
        var cells = Array(repeating: Array(repeating: Character(" "), count: 160), count: 80)
        let chars = Array(raw); var i = 0, row = 0, col = 0
        while i < chars.count {
            let c = chars[i]; i += 1
            if c == "\u{1b}" {
                guard i < chars.count else { break }
                let kind = chars[i]; i += 1
                if kind == "[" {
                    var params = ""
                    while i < chars.count && !(chars[i].asciiValue.map { (64...126).contains($0) } ?? false) { params.append(chars[i]); i += 1 }
                    guard i < chars.count else { break }
                    let final = chars[i]; i += 1
                    let nums = params.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
                    let n = max(1, nums.first ?? 1)
                    switch final {
                    case "H", "f": row = max(0, (nums.first ?? 1) - 1); col = max(0, (nums.count > 1 ? nums[1] : 1) - 1)
                    case "G": col = n - 1
                    case "A": row = max(0, row - n)
                    case "B": row += n
                    case "C": col += n
                    case "D": col = max(0, col - n)
                    case "J": if nums.first == 2 { cells = Array(repeating: Array(repeating: " ", count: 160), count: 80) }
                    case "K": if row < 80 { for x in min(col, 159)..<160 { cells[row][x] = " " } }
                    default: break
                    }
                } else if kind == "]" {
                    while i < chars.count && chars[i] != "\u{7}" { if chars[i] == "\u{1b}", i + 1 < chars.count, chars[i + 1] == "\\" { i += 1; break }; i += 1 }; i += 1
                } else if kind == "(" { i += 1 }
                continue
            }
            if c == "\r" { col = 0; continue }
            if c == "\n" { row += 1; continue }
            if let code = c.asciiValue, code < 32 { continue }
            if col >= 160 { row += 1; col = 0 }
            if row >= 80 { cells.removeFirst(); cells.append(Array(repeating: " ", count: 160)); row = 79 }
            cells[row][col] = c; col += 1
        }
        return cells.map { String($0).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    }
}
