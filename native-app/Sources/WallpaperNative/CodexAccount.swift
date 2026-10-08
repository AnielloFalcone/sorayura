import Foundation
import Darwin

struct CodexAccountSnapshot: Sendable {
    var quota: AgentQuota?
    var costs: [String: Double] = [:]
    var error: String?
    var date: Date?
}
actor CodexAccountReader {
    static let defaultExecutable = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
    static func quota(_ result: [String: Any], now: Date = Date()) -> AgentQuota? {
        let buckets = result["rateLimitsByLimitId"] as? [String: Any]
        guard let value = (buckets?["codex"] ?? result["rateLimits"]) as? [String: Any] else { return nil }
        func limit(_ name: String) -> AgentLimit? {
            guard let d = value[name] as? [String: Any], let used = d["usedPercent"] as? NSNumber, let reset = d["resetsAt"] as? NSNumber else { return nil }
            return AgentLimit(used: min(100, max(0, used.doubleValue)), reset: Date(timeIntervalSince1970: reset.doubleValue), minutes: (d["windowDurationMins"] as? NSNumber)?.doubleValue ?? 0)
        }
        return AgentQuota(date: now, plan: value["planType"] as? String, session: limit("primary"), week: limit("secondary"))
    }
    func read(executable: String, threads: [String]) -> CodexAccountSnapshot {
        var snapshot = CodexAccountSnapshot()
        guard FileManager.default.isExecutableFile(atPath: executable) else { snapshot.error = "Seleziona l'eseguibile Codex CLI."; return snapshot }
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        // A child that exits must yield EPIPE, never terminate the desktop app.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        defer { timeout.cancel(); if process.isRunning { process.terminate() }; try? input.fileHandleForWriting.close(); try? output.fileHandleForReading.close() }
        func send(_ value: [String: Any]) throws {
            try input.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: value) + Data([10]))
        }
        func receive() throws -> Data {
            var bytes = [UInt8](repeating: 0, count: 65_536)
            while true {
                // One pipe read returns available bytes. Foundation's bounded read
                // can wait for a full buffer, deadlocking the initialize handshake.
                let count = Darwin.read(output.fileHandleForReading.fileDescriptor, &bytes, bytes.count)
                if count >= 0 { return Data(bytes.prefix(count)) }
                if errno != EINTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            }
        }
        do {
            try process.run()
            DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: timeout)
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
            try send(["id":0,"method":"initialize","params":["clientInfo":["name":"mac_system_wallpaper","version":version]]])
            var pending = Set<Int>(), initialized = false
            var buffer = Data()
            while true {
                let chunk = try receive()
                if chunk.isEmpty { break }
                buffer.append(chunk)
                guard buffer.count < 8_000_000 else { throw SettingsError.invalid("Risposta Codex troppo grande.") }
                while let end = buffer.firstIndex(of: 10) {
                    let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
                    guard let response = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let id = response["id"] as? Int else { continue }
                    if id == 0 {
                        guard response["error"] == nil else { throw SettingsError.invalid("Codex non accetta il collegamento.") }
                        try send(["method":"initialized"])
                        try send(["id":1,"method":"account/rateLimits/read"]); pending.insert(1)
                        for (index, thread) in threads.prefix(8).enumerated() {
                            let requestID = index + 2; pending.insert(requestID)
                            try send(["id":requestID,"method":"account/usage/read","params":["threadId":thread]])
                        }
                        initialized = true
                    } else {
                        pending.remove(id)
                        if let result = response["result"] as? [String: Any] {
                            if id == 1 { snapshot.quota = Self.quota(result) }
                            else if let usage = result["threadUsage"] as? [String: Any], let amount = usage["estimatedUsageUsdMicros"] as? NSNumber, let thread = usage["threadId"] as? String, amount.doubleValue >= 0 {
                                snapshot.costs[thread] = amount.doubleValue / 1_000_000
                            }
                        } else if id == 1 { snapshot.error = "Limiti Codex non disponibili: verifica il login nel client Codex." }
                    }
                }
                if initialized && pending.isEmpty { snapshot.date = Date(); return snapshot }
            }
            snapshot.error = "Il collegamento Codex è scaduto o è stato interrotto."
        } catch { snapshot.error = LF("Collegamento Codex non disponibile: \(error.localizedDescription)") }
        return snapshot
    }
}
