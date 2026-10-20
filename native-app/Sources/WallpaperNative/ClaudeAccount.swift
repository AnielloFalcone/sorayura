import Foundation
import Darwin

struct ClaudeAccountSnapshot: Sendable {
    var quota: AgentQuota?
    var error: String?
}

actor ClaudeAccountReader {
    static let arguments = ["--print", "--input-format", "stream-json", "--output-format", "stream-json",
        "--verbose", "--no-session-persistence", "--tools", "", "--strict-mcp-config",
        "--mcp-config", "{\"mcpServers\":{}}", "--setting-sources", "", "--settings", "{\"disableAllHooks\":true}"]

    static func quota(_ result: [String: Any], observed: Date) -> AgentQuota? {
        guard result["rate_limits_available"] as? Bool == true,
              let limits = result["rate_limits"] as? [String: Any] else { return nil }
        func limit(_ key: String, minutes: Double) -> AgentLimit? {
            guard let value = limits[key] as? [String: Any], let used = value["utilization"] as? NSNumber,
                  CFGetTypeID(used) != CFBooleanGetTypeID(), used.doubleValue.isFinite,
                  (0...100).contains(used.doubleValue) else { return nil }
            var reset: Date?
            if let raw = value["resets_at"], !(raw is NSNull) {
                guard let text = raw as? String else { return nil }
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                reset = formatter.date(from: text)
                if reset == nil { formatter.formatOptions = [.withInternetDateTime]; reset = formatter.date(from: text) }
                guard let reset, reset > observed else { return nil }
            }
            return AgentLimit(used: used.doubleValue, reset: reset, minutes: minutes)
        }
        let session = limit("five_hour", minutes: 300), week = limit("seven_day", minutes: 10080)
        guard session != nil || week != nil else { return nil }
        return AgentQuota(date: observed, plan: nil, session: session, week: week)
    }

    static func isRecent(_ observed: Date, now: Date = Date()) -> Bool {
        // Claude Code 2.1.236 throttles cache timestamp writes to five minutes.
        (-5...330).contains(now.timeIntervalSince(observed))
    }

    static func cacheDate(home: URL) -> Date? {
        guard let data = try? Data(contentsOf: home.appending(path: ".claude.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = (json["cachedUsageUtilization"] as? [String: Any])?["fetchedAtMs"] as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite, value.doubleValue > 0 else { return nil }
        return Date(timeIntervalSince1970: value.doubleValue / 1000)
    }

    func read() -> ClaudeAccountSnapshot {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let executable = [home.appending(path: ".local/bin/claude").path, "/opt/homebrew/bin/claude", "/usr/local/bin/claude"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return .init(error: "Claude Code non installato.")
        }
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Self.arguments
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        env["HOME"] = home.path; env["USER"] = NSUserName(); env["DISABLE_AUTOUPDATER"] = "1"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        // Preserve network configuration and privacy opt-outs when skipping user settings.
        if let data = try? Data(contentsOf: home.appending(path: ".claude/settings.json")),
           let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let values = settings["env"] as? [String: Any] {
            for key in ["HTTPS_PROXY", "HTTP_PROXY", "NO_PROXY", "NODE_EXTRA_CA_CERTS", "DISABLE_TELEMETRY", "DISABLE_ERROR_REPORTING", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] {
                if let text = values[key] as? String { env[key] = text }
                else if let number = values[key] as? NSNumber { env[key] = CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue }
            }
        }
        process.environment = env
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        _ = fcntl(output.fileHandleForReading.fileDescriptor, F_SETFL, O_NONBLOCK)
        func stop() {
            try? input.fileHandleForWriting.close()
            let deadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { process.terminate() }
            let terminateDeadline = Date().addingTimeInterval(1)
            while process.isRunning && Date() < terminateDeadline { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        var started = false
        defer { if started { stop() }; try? output.fileHandleForReading.close() }
        do {
            try process.run(); started = true
            let deadline = Date().addingTimeInterval(25)
            var buffer = Data(), total = 0
            for request in ["initialize", "get_usage"] {
                let body: [String: Any] = request == "initialize" ? ["subtype": request] : ["subtype": request, "skip_behaviors": true]
                try input.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: ["type":"control_request", "request_id":request, "request":body]) + Data([10]))
                var answered = false
                while !answered && Date() < deadline {
                    var bytes = [UInt8](repeating: 0, count: 16384)
                    let count = Darwin.read(output.fileHandleForReading.fileDescriptor, &bytes, bytes.count)
                    if count > 0 { buffer.append(contentsOf: bytes.prefix(count)); total += count }
                    else if count == 0 { throw SettingsError.invalid("Lettura Claude Code non riuscita.") }
                    else if errno != EAGAIN && errno != EINTR { throw SettingsError.invalid("Lettura Claude Code non riuscita.") }
                    guard total <= 2_000_000 else { throw SettingsError.invalid("Lettura Claude Code non riuscita.") }
                    while let end = buffer.firstIndex(of: 10) {
                        let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
                        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                              message["type"] as? String == "control_response",
                              let response = message["response"] as? [String: Any], response["request_id"] as? String == request else { continue }
                        guard response["subtype"] as? String == "success" else {
                            throw SettingsError.invalid("Aggiorna Claude Code e verifica il login per leggere i limiti.")
                        }
                        answered = true
                        if request == "get_usage" {
                            guard let result = response["response"] as? [String: Any], result["rate_limits_available"] as? Bool == true else {
                                throw SettingsError.invalid("Claude Code richiede il login.")
                            }
                            stop(); started = false
                            guard let observed = Self.cacheDate(home: home), Self.isRecent(observed),
                                  let quota = Self.quota(result, observed: observed) else {
                                throw SettingsError.invalid("Claude non ha restituito limiti aggiornati. Riproveremo automaticamente.")
                            }
                            return .init(quota: quota)
                        }
                        break
                    }
                    if !answered { Thread.sleep(forTimeInterval: 0.05) }
                }
                if !answered { throw SettingsError.invalid("Claude non ha restituito limiti aggiornati. Riproveremo automaticamente.") }
            }
        } catch let error as SettingsError { return .init(error: error.localizedDescription) }
        catch { return .init(error: "Lettura Claude Code non riuscita.") }
        return .init(error: "Lettura Claude Code non riuscita.")
    }
}
