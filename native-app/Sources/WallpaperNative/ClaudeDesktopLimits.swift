import Foundation
import CoreFoundation

struct ClaudeDesktopLimits: Sendable {
    var quota: AgentQuota
    var opus: AgentLimit?
    var sonnet: AgentLimit?
    static var file: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Claude/plan-usage-history.json")
    }
    static func read() -> Self? {
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4_194_304,
              let data = try? Data(contentsOf: file) else { return nil }
        return decode(data)
    }
    static func decode(_ data: Data, now: Date = Date()) -> Self? {
        guard data.count <= 4_194_304,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? Int, [1, 2].contains(version),
              let samples = object["samples"] as? [[String: Any]] else { return nil }
        let valid = samples.compactMap { item -> (Date, [String: Any])? in
            guard let t = item["t"] as? NSNumber, CFGetTypeID(t) != CFBooleanGetTypeID(), t.doubleValue.isFinite else { return nil }
            let date = Date(timeIntervalSince1970: t.doubleValue / 1000)
            guard date <= now.addingTimeInterval(300), date > .distantPast else { return nil }
            return (date, version == 1 ? item : (item["u"] as? [String: Any] ?? [:]))
        }
        guard let latest = valid.max(by: { $0.0 < $1.0 }) else { return nil }
        func limit(_ key: String, minutes: Double) -> AgentLimit? {
            guard let value = latest.1[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                  value.doubleValue.isFinite, now.timeIntervalSince(latest.0) < minutes * 60 else { return nil }
            return AgentLimit(used: min(100, max(0, value.doubleValue)), reset: nil, minutes: minutes)
        }
        let quota = AgentQuota(date: latest.0, plan: nil, session: limit("fh", minutes: 300), week: limit("sd", minutes: 10080))
        let result = Self(quota: quota, opus: limit("so", minutes: 10080), sonnet: limit("sn", minutes: 10080))
        return quota.session != nil || quota.week != nil || result.opus != nil || result.sonnet != nil ? result : nil
    }
}
