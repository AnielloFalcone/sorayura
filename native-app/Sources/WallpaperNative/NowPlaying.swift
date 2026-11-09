import Foundation

enum SystemNowPlaying {
    static let commands = ["play", "pause", "playpause", "previous track", "next track"]

    struct Reading: Decodable {
        var title: String?
        var artist: String?
        var album: String?
        var identifier: String?
        var playing: Bool
        var artwork: Data?

        var snapshot: SpotifySnapshot {
            guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return SpotifySnapshot(title: "Nessun contenuto in riproduzione")
            }
            return SpotifySnapshot(title: title, artist: artist ?? "", album: album ?? "", playing: playing,
                                   available: true, artwork: artwork,
                                   trackID: [identifier ?? "", title, artist ?? "", album ?? ""].joined(separator: "\u{1F}"),
                                   supportedCommands: SystemNowPlaying.commands)
        }
    }

    // MediaRemote is private. Load it in the system Perl process, and keep failure local to this source.
    static func run(_ action: String) throws -> Data {
        guard let resources = Bundle.main.resourceURL, let frameworks = Bundle.main.privateFrameworksURL else {
            throw SettingsError.invalid("In riproduzione non disponibile.")
        }
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [resources.appending(path: "now-playing.pl").path,
                             frameworks.appending(path: "SorayuraNowPlaying.dylib").path, action]
        process.environment = [:]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw SettingsError.invalid("In riproduzione non disponibile.") }
        return data
    }
}
