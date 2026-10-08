import AppKit
import SwiftUI

struct SpotifySnapshot: Sendable, Equatable {
    var title = "Spotify"
    var artist = ""
    var album = ""
    var playing = false
    var available = false
    var artwork: Data?
    var error: String?
    var denied = false
}
actor SpotifyReader {
    private var artworkURL = ""
    private var artwork: Data?
    private func script(_ source: String) throws -> NSAppleEventDescriptor {
        var error: NSDictionary?
        let result = NSAppleScript(source: "with timeout of 3 seconds\n" + source + "\nend timeout")?.executeAndReturnError(&error)
        if let error { throw NSError(domain: "Spotify", code: (error[NSAppleScript.errorNumber] as? Int) ?? -1) }
        guard let result else { throw NSError(domain: "Spotify", code: -1) }
        return result
    }
    func read(running: Bool) async -> SpotifySnapshot {
        guard running else { return SpotifySnapshot(title: "Apri Spotify") }
        do {
            let descriptor = try script("""
            tell application id "com.spotify.client"
                set t to current track
                return {name of t, artist of t, album of t, (player state is playing), artwork url of t}
            end tell
            """)
            let url = descriptor.atIndex(5)?.stringValue ?? ""
            if url != artworkURL {
                artworkURL = url; artwork = nil
                if let remote = URL(string: url), remote.scheme == "https", let host = remote.host, host == "i.scdn.co" || host.hasSuffix(".spotifycdn.com") {
                    var request = URLRequest(url: remote); request.timeoutInterval = 4
                    if let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200, data.count < 5_000_000 { artwork = data }
                }
            }
            return SpotifySnapshot(title: descriptor.atIndex(1)?.stringValue ?? "Nessun brano", artist: descriptor.atIndex(2)?.stringValue ?? "", album: descriptor.atIndex(3)?.stringValue ?? "", playing: descriptor.atIndex(4)?.booleanValue ?? false, available: true, artwork: artwork)
        } catch {
            let denied = (error as NSError).code == -1743
            return SpotifySnapshot(title: "Spotify", error: denied ? "Consenti Spotify in Privacy e sicurezza → Automazione, poi premi Riprova." : "Nessun brano disponibile o Spotify non risponde.", denied: denied)
        }
    }
    func command(_ name: String) throws {
        guard ["playpause", "previous track", "next track"].contains(name) else { return }
        _ = try script("tell application id \"com.spotify.client\" to " + name)
    }
}
struct SpotifyWidget: View {
    @Environment(Model.self) private var model
    var body: some View {
        let _ = LocalizationSettings.shared.choice
        VStack(alignment: .leading, spacing: 8) {
            Label("Spotify", systemImage: "music.note").font(.system(size: 12, weight: .semibold))
            if model.prefs.spotifyEnabled != true { Text(L("Attiva da Integrazioni")).font(.caption).foregroundStyle(.secondary) }
            else {
                HStack(spacing: 10) {
                    if let data = model.spotify.artwork, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().scaledToFill().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.spotify.available ? model.spotify.title : L(model.spotify.title)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(model.spotify.artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        if model.widgetUnits("spotify", axis: "height") > 1 { Text(model.spotify.album).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
                if let error = model.spotify.error { Text(L(error)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(3) }
                Spacer(minLength: 0)
                HStack {
                    musicButton("backward.end.fill", command: "previous track", label: L("Brano precedente"))
                    musicButton(model.spotify.playing ? "pause.fill" : "play.fill", command: "playpause", label: L("Riproduci o pausa"))
                    musicButton("forward.end.fill", command: "next track", label: L("Brano successivo"))
                }.frame(height: 28)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func musicButton(_ icon: String, command: String, label: String) -> some View {
        Button { model.spotifyCommand(command) } label: { Image(systemName: icon).frame(maxWidth: .infinity) }
            .buttonStyle(.plain).disabled(!model.spotify.available).help(L(label))
    }
}
