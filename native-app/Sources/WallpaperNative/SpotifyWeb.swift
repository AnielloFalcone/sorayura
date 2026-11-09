import AppKit

struct SpotifyWebSnapshot: Codable, Sendable {
    var title: String
    var artist: String
    var album: String
    var available: Bool
    var playing: Bool
    var artworkURL: String
    var trackID: String
    var volume: Int
    var shuffle: Bool
    var repeatEnabled: Bool
    var supportedCommands: [String]
    var session: String? = nil
    var updated: Double? = nil
    var error: String? = nil

    var valid: Bool {
        [title, artist, album, artworkURL, trackID].allSatisfy { $0.utf8.count <= 2048 } &&
        (0...100).contains(volume) && supportedCommands.count <= 12 &&
        supportedCommands.allSatisfy { SpotifyWebBridge.commands.contains($0) } &&
        (artworkURL.isEmpty || SpotifyWebBridge.artworkURL(artworkURL) != nil)
    }
}

enum SpotifyWebBridge {
    static let extensionID = "inhafmkeidjjklmcdjddjlbohbbafepi"
    static let hostName = "dev.sorayura.spotify_web"
    static let changed = Notification.Name("dev.sorayura.spotifyWebChanged")
    static let command = Notification.Name("dev.sorayura.spotifyWebCommand")
    static let commands: Set<String> = ["play", "pause", "playpause", "previous track", "next track", "shuffle", "repeat", "volumeUp", "volumeDown"]
    static var directory: URL { FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/dev.aniello.macsystemwallpaper/spotify-web") }
    static var snapshotURL: URL { directory.appending(path: "snapshot.json") }
    static func artworkURL(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme == "https", url.user == nil, url.password == nil,
              let host = url.host, host == "i.scdn.co" || host.hasSuffix(".spotifycdn.com") else { return nil }
        return url
    }
    static func read(now: Date = Date()) -> SpotifyWebSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL), data.count <= 65536,
              let value = try? JSONDecoder().decode(SpotifyWebSnapshot.self, from: data), value.valid,
              let timestamp = value.updated, let session = value.session, UUID(uuidString: session) != nil,
              (0...15).contains(now.timeIntervalSince1970 - timestamp) else { return nil }
        return value
    }
    static func send(_ action: String, session: String?) throws {
        guard commands.contains(action), let session, let current = read(), current.session == session else {
            throw SettingsError.invalid("Spotify Web non è collegato. Apri la scheda Spotify e controlla l’estensione.")
        }
        DistributedNotificationCenter.default().postNotificationName(command, object: session, userInfo: ["action": action], deliverImmediately: true)
    }
    @MainActor static func install() throws -> URL {
        guard let resources = Bundle.main.resourceURL else { throw SettingsError.invalid("Risorse mancanti.") }
        let fm = FileManager.default
        let folder = directory.appending(path: "Chrome extension")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for name in ["manifest.json", "page.js", "content.js", "worker.js", "icons/icon16.png", "icons/icon32.png", "icons/icon48.png", "icons/icon128.png"] {
            let data = try Data(contentsOf: resources.appending(path: "SpotifyWebExtension/\(name)"))
            let target = folder.appending(path: name)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        }
        let host = resources.appending(path: "spotify-web-host")
        guard fm.isExecutableFile(atPath: host.path) else { throw SettingsError.invalid("Risorse mancanti.") }
        let registration = fm.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Google/Chrome/NativeMessagingHosts")
        try fm.createDirectory(at: registration, withIntermediateDirectories: true)
        let manifest: [String: Any] = ["name": hostName, "description": "Sorayura Spotify Web", "path": host.path,
                                     "type": "stdio", "allowed_origins": ["chrome-extension://\(extensionID)/"]]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: registration.appending(path: hostName + ".json"), options: .atomic)
        return folder
    }
}

/// Chrome alone owns the pipe; only allowlisted transport commands travel back.
final class SpotifyNativeHost: @unchecked Sendable {
    private let session = UUID().uuidString
    private let outputLock = NSLock()
    private var observer: NSObjectProtocol?
    static func frame(_ data: Data) -> Data {
        var length = UInt32(data.count).littleEndian
        var result = Data(bytes: &length, count: 4); result.append(data); return result
    }
    static func readMessage(_ input: FileHandle) throws -> Data? {
        func exact(_ count: Int) throws -> Data? {
            var data = Data()
            while data.count < count {
                guard let part = try input.read(upToCount: count - data.count), !part.isEmpty else {
                    if data.isEmpty { return nil }
                    throw SettingsError.invalid("Truncated native message")
                }
                data.append(part)
            }
            return data
        }
        guard let header = try exact(4) else { return nil }
        let length = header.enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) }
        guard (1...65536).contains(length), let body = try exact(length) else { throw SettingsError.invalid("Invalid native message size") }
        return body
    }
    private func send(_ object: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        outputLock.lock(); defer { outputLock.unlock() }
        try? FileHandle.standardOutput.write(contentsOf: Self.frame(data))
    }
    @MainActor static func run() {
        guard CommandLine.arguments.contains("chrome-extension://\(SpotifyWebBridge.extensionID)/") else { exit(1) }
        let host = SpotifyNativeHost()
        host.observer = DistributedNotificationCenter.default().addObserver(forName: SpotifyWebBridge.command, object: host.session, queue: .main) { note in
            guard let action = note.userInfo?["action"] as? String, SpotifyWebBridge.commands.contains(action) else { return }
            host.send(["type": "command", "action": action])
        }
        DispatchQueue.global(qos: .utility).async { host.readLoop() }
        RunLoop.main.run()
    }
    private func readLoop() {
        var latest: SpotifyWebSnapshot?
        do {
            try FileManager.default.createDirectory(at: SpotifyWebBridge.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            while let data = try Self.readMessage(.standardInput) {
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let type = object["type"] as? String else { continue }
                if type == "snapshot", let raw = object["snapshot"], JSONSerialization.isValidJSONObject(raw) {
                    let bytes = try JSONSerialization.data(withJSONObject: raw)
                    if var value = try? JSONDecoder().decode(SpotifyWebSnapshot.self, from: bytes), value.valid {
                        value.session = session; value.updated = Date().timeIntervalSince1970; value.error = nil
                        latest = value
                    }
                } else if type == "error", var value = latest {
                    value.error = "Comando non disponibile in Spotify Web."
                    latest = value
                } else { continue }
                if let latest {
                    try JSONEncoder().encode(latest).write(to: SpotifyWebBridge.snapshotURL, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: SpotifyWebBridge.snapshotURL.path)
                    DistributedNotificationCenter.default().postNotificationName(SpotifyWebBridge.changed, object: nil, userInfo: nil, deliverImmediately: true)
                }
            }
        } catch { fputs("Spotify Web bridge closed: \(error)\n", stderr) }
        if SpotifyWebBridge.read()?.session == session { try? FileManager.default.removeItem(at: SpotifyWebBridge.snapshotURL) }
        DistributedNotificationCenter.default().postNotificationName(SpotifyWebBridge.changed, object: nil, userInfo: nil, deliverImmediately: true)
        exit(0)
    }
}
