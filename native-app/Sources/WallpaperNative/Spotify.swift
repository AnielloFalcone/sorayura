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
    var volume = 50
    var shuffle = false
    var repeatEnabled = false
    var trackID = ""
    var webSession: String?
    var supportedCommands: [String]?
    mutating func predict(_ command:String) {
        switch command {
        case "playpause": playing.toggle()
        case "shuffle": shuffle.toggle()
        case "repeat": repeatEnabled.toggle()
        case "volumeDown": volume=max(0,volume-10)
        case "volumeUp": volume=min(100,volume+10)
        default: break
        }
    }
}
/// Keep the requested state stable while Spotify acknowledges a transport change.
/// Late notifications are refresh triggers, never a competing UI state source.
struct SpotifyPlaybackIntent {
    var playing:Bool
    var trackID:String
    var deadline:Date
    func reconcile(_ sample:SpotifySnapshot, now:Date = Date())->Bool {
        guard sample.available, sample.trackID == trackID, now < deadline else { return sample.playing }
        return playing
    }
}
actor SpotifyReader {
    private var artworkURL = ""
    private var artwork: Data?
    private var artworkAttempt = Date.distantPast
    private var systemArtwork: Data?
    private var systemTrack = ""
    private var systemArtworkAttempt = Date.distantPast

    func read(source: String?, running: Bool, includeArtwork: Bool) async -> SpotifySnapshot {
        switch source {
        case "nowPlaying": return readNowPlaying(includeArtwork: includeArtwork)
        case "web": return await readWeb(includeArtwork: includeArtwork)
        default: return await read(running: running, includeArtwork: includeArtwork)
        }
    }
    private func readNowPlaying(includeArtwork: Bool) -> SpotifySnapshot {
        let fetchArtwork = includeArtwork && Date().timeIntervalSince(systemArtworkAttempt) > 15
        if fetchArtwork { systemArtworkAttempt = Date() }
        do {
            let data = try SystemNowPlaying.run(fetchArtwork ? "artwork" : "read")
            var value = try JSONDecoder().decode(SystemNowPlaying.Reading.self, from: data).snapshot
            if value.trackID != systemTrack {
                systemTrack = value.trackID
                systemArtwork = nil
                systemArtworkAttempt = fetchArtwork ? Date() : .distantPast
            }
            if let cover = value.artwork { systemArtwork = cover }
            value.artwork = systemArtwork
            return value
        } catch {
            return SpotifySnapshot(title: "In riproduzione", error: "In riproduzione non disponibile.")
        }
    }
    func commandNowPlaying(_ action: String) throws {
        _ = try SystemNowPlaying.run(action)
    }

    private func script(_ source: String) throws -> NSAppleEventDescriptor {
        var error: NSDictionary?
        let result = NSAppleScript(source: "with timeout of 3 seconds\n" + source + "\nend timeout")?.executeAndReturnError(&error)
        if let error { throw NSError(domain: "Spotify", code: (error[NSAppleScript.errorNumber] as? Int) ?? -1) }
        guard let result else { throw NSError(domain: "Spotify", code: -1) }
        return result
    }
    func read(running: Bool, includeArtwork:Bool = true) async -> SpotifySnapshot {
        guard running else { return SpotifySnapshot(title: "Apri Spotify") }
        do {
            let descriptor = try script("""
            tell application id "com.spotify.client"
                set t to current track
                return {name of t, artist of t, album of t, (player state is playing), artwork url of t, sound volume, shuffling, repeating, id of t}
            end tell
            """)
            let url = descriptor.atIndex(5)?.stringValue ?? ""
            let cover = await cover(url, enabled: includeArtwork)
            return SpotifySnapshot(title: descriptor.atIndex(1)?.stringValue ?? "Nessun brano", artist: descriptor.atIndex(2)?.stringValue ?? "", album: descriptor.atIndex(3)?.stringValue ?? "", playing: descriptor.atIndex(4)?.booleanValue ?? false, available: true, artwork: cover, volume: min(100, max(0, Int(descriptor.atIndex(6)?.int32Value ?? 50))), shuffle: descriptor.atIndex(7)?.booleanValue ?? false, repeatEnabled: descriptor.atIndex(8)?.booleanValue ?? false, trackID: descriptor.atIndex(9)?.stringValue ?? "")
        } catch {
            let denied = (error as NSError).code == -1743
            return SpotifySnapshot(title: "Spotify", error: denied ? "Consenti Spotify in Privacy e sicurezza → Automazione, poi premi Riprova." : "Nessun brano disponibile o Spotify non risponde.", denied: denied)
        }
    }
    private func cover(_ url: String, enabled: Bool) async -> Data? {
        if url != artworkURL { artworkURL = url; artwork = nil; artworkAttempt = .distantPast }
        if enabled, artwork == nil, Date().timeIntervalSince(artworkAttempt) > 15,
           let remote = SpotifyWebBridge.artworkURL(url) {
            artworkAttempt = Date()
            var request = URLRequest(url: remote); request.timeoutInterval = 4
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200, data.count < 5_000_000, url == artworkURL { artwork = data }
        }
        return artwork
    }
    func readWeb(includeArtwork: Bool = true) async -> SpotifySnapshot {
        guard let value = SpotifyWebBridge.read() else {
            return SpotifySnapshot(title: "Apri Spotify Web", error: "Collega l’estensione Chrome da Impostazioni → Musica e apri Spotify Web.")
        }
        let art = await cover(value.artworkURL, enabled: includeArtwork)
        return SpotifySnapshot(title: value.available ? value.title : "Apri Spotify Web", artist: value.artist,
            album: value.album, playing: value.playing, available: value.available, artwork: art, error: value.error,
            volume: value.volume, shuffle: value.shuffle, repeatEnabled: value.repeatEnabled, trackID: value.trackID,
            webSession: value.session, supportedCommands: value.supportedCommands)
    }
    func command(_ name: String) throws {
        let source: String
        switch name {
        case "playpause", "play", "pause", "previous track", "next track": source = name
        case "shuffle": source = "set shuffling to not shuffling"
        case "repeat": source = "set repeating to not repeating"
        case "volumeDown": source = "set v to sound volume\nif v < 10 then\nset sound volume to 0\nelse\nset sound volume to (v - 10)\nend if"
        case "volumeUp": source = "set v to sound volume\nif v > 90 then\nset sound volume to 100\nelse\nset sound volume to (v + 10)\nend if"
        default: return
        }
        _ = try script("tell application id \"com.spotify.client\"\n" + source + "\nend tell")

    }
}
struct SpotifyShortcut: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var link: String
    static func webURL(_ text: String) -> URL? {
        guard let uri = uri(text) else { return nil }
        let parts = uri.absoluteString.split(separator: ":")
        return URL(string: "https://open.spotify.com/\(parts[1])/\(parts[2])")
    }
    static func uri(_ text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String]
        if text.hasPrefix("spotify:") { parts = text.split(separator: ":").map(String.init); guard parts.count == 3 else { return nil }; parts.removeFirst() }
        else {
            guard let url = URL(string: text), url.scheme == "https", url.host?.lowercased() == "open.spotify.com", url.user == nil, url.password == nil, url.port == nil else { return nil }
            parts = url.path.split(separator: "/").map(String.init)
            if parts.first?.hasPrefix("intl-") == true { parts.removeFirst() }
        }
        guard parts.count == 2, ["playlist", "album", "track"].contains(parts[0]), parts[1].count == 22,
              parts[1].utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else { return nil }
        return URL(string: "spotify:\(parts[0]):\(parts[1])")
    }
}

/// Shared geometry keeps desktop hit surfaces aligned with the visible controls.
struct SpotifyLayout {
    var artwork: CGRect
    var info: CGRect
    var controls: [(String, CGRect)] = []
    var expanded: Bool
    var volumeBar: CGRect?
    static func minimumHeight(expanded: Bool, shortcuts: Int) -> Double {
        guard expanded else { return 88 }
        let rows = (min(6, max(0, shortcuts)) + 2) / 3
        return Double(230 + rows * 40 + (rows > 0 ? 8 : 0))
    }

    init(size: CGSize, expanded: Bool, shortcuts: Int, nowPlaying: Bool = false) {
        let w = max(1, size.width), h = max(1, size.height)
        if w < 120 || h < 80 {
            self.expanded=false;artwork = .zero;info = .zero
            if !nowPlaying { controls=[("open",CGRect(x:0,y:0,width:min(28,w),height:min(28,h)))] };return
        }
        let count = min(6,max(0,shortcuts)), rows = (count+2)/3
        self.expanded = expanded && w >= 240 && h >= Self.minimumHeight(expanded: true, shortcuts: count)
        let bottom = self.expanded ? 120.0 + Double(rows*40 + (rows > 0 ? 8 : 0)) : 40.0
        let cover = self.expanded ? min(140, max(64, h - bottom - 34), w * 0.4) : min(48, max(20, h - 32 - 24))
        artwork = CGRect(x: 0, y: 24, width: cover, height: cover)
        info = CGRect(x: cover + 12, y: 24, width: max(1, w - cover - 12), height: cover)
        if !nowPlaying { controls.append(("open", CGRect(x: max(0,w-28), y: 0, width: 28, height: 24))) }
        let transportY = self.expanded ? h - bottom + 4 : h - 32
        let names = self.expanded && !nowPlaying ? ["shuffle", "previous track", "playpause", "next track", "repeat"] : ["previous track", "playpause", "next track"]
        let strip=min(w,320), width = strip / Double(names.count), left=(w-strip)/2
        for (i, name) in names.enumerated() { controls.append((name, CGRect(x: left+Double(i)*width+2, y: transportY, width: max(1,width-4), height: self.expanded ? 44 : 32))) }
        if self.expanded {
            if !nowPlaying {
                volumeBar=CGRect(x:44,y:transportY+64,width:max(1,w-88),height:4)
                controls.append(("volumeDown", CGRect(x: 0, y: transportY + 52, width: 36, height: 28)))
                controls.append(("volumeUp", CGRect(x: w-36, y: transportY + 52, width: 36, height: 28)))
            }
            let columns = min(3,count)
            for i in 0..<count {
                controls.append(("shortcut:\(i)",CGRect(x:Double(i%columns)*w/Double(columns)+3,y:h-Double(rows*40)+Double(i/columns*40)+8,width:w/Double(columns)-6,height:32)))
            }
        }
    }
    func action(at point: CGPoint, available: Bool) -> String? {
        if let action = controls.first(where: { $0.1.contains(point) })?.0 { return action }
        return !available && info.contains(point) ? "open" : nil
    }
}

struct SpotifyWidget: View {
    var appleMusic = false
    var interactionID = "settings"
    @Environment(Model.self) private var model
    private var nowPlaying: Bool { !appleMusic && model.prefs.spotifySource == "nowPlaying" }
    private var snapshot: SpotifySnapshot { appleMusic ? model.appleMusic : model.spotify }
    private var enabled: Bool { appleMusic ? model.prefs.appleMusicEnabled == true : model.prefs.spotifyEnabled == true }
    private var expanded: Bool { (appleMusic ? model.prefs.appleMusicDisplay : model.prefs.spotifyDisplay) == "expanded" }
    private func action(_ command: String) { if appleMusic { model.appleMusicAction(command) } else { model.spotifyAction(command) } }
    private func supports(_ command: String) -> Bool { appleMusic ? model.appleMusicSupports(command) : model.spotifySupports(command) }
    var body: some View {
        let _ = LocalizationSettings.shared.choice
        GeometryReader { geo in
            let shortcuts = appleMusic ? [] : Array((model.prefs.spotifyShortcuts ?? []).prefix(6))
            let layout = SpotifyLayout(size: geo.size, expanded: expanded, shortcuts: shortcuts.count, nowPlaying: nowPlaying)
            ZStack(alignment: .topLeading) {
                if layout.info.width > 0 { Label(appleMusic ? "Apple Music" : nowPlaying ? L("In riproduzione") : "Spotify", systemImage: "music.note").font(.system(size: 12, weight: .semibold)) }
                if !enabled {
                    Text(L("Attiva da Musica")).font(.caption).position(x:geo.size.width/2, y:50)
                } else {
                    artwork.frame(width:layout.artwork.width,height:layout.artwork.height).clipShape(RoundedRectangle(cornerRadius:layout.expanded ? 14 : 8)).position(x:layout.artwork.midX,y:layout.artwork.midY)
                    VStack(alignment:.leading,spacing:5) {
                        if ["Apri Spotify", "Apri Spotify Web", "Apri Musica"].contains(snapshot.title) {
                            Button(L(snapshot.title)) { action("open") }.buttonStyle(.plain).foregroundStyle(.tint)
                        } else { Text(snapshot.available ? snapshot.title : L(snapshot.title)).font(.system(size:layout.expanded ? 20 : 13,weight:.semibold)).lineLimit(layout.expanded && layout.info.height >= 110 ? 2 : 1) }
                        if layout.info.height >= 32 { Text(snapshot.artist).font(.system(size:layout.expanded ? 13 : 11)).foregroundStyle(.secondary).lineLimit(1) }
                        if layout.expanded { Text(snapshot.album).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1) }
                        if let error = snapshot.error { Text(L(error)).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(2) }
                    }.frame(width:layout.info.width,height:layout.info.height,alignment:.topLeading).position(x:layout.info.midX,y:layout.info.midY).opacity(layout.info.width > 0 ? 1:0)
                    ForEach(layout.controls, id: \.0) { item in
                        control(item.0, expanded:layout.expanded, shortcuts:shortcuts).frame(width:item.1.width,height:item.1.height).position(x:item.1.midX,y:item.1.midY)
                    }
                    if let bar=layout.volumeBar {
                        ProgressView(value:snapshot.available ? Double(snapshot.volume):0,total:100).tint(.green).frame(width:bar.width,height:bar.height).position(x:bar.midX,y:bar.midY)
                        Text(snapshot.available ? "\(snapshot.volume)%" : "—").font(.system(size:9)).monospacedDigit().foregroundStyle(.secondary).position(x:bar.midX,y:bar.midY+19)
                    }
                }
            }.frame(width:geo.size.width,height:geo.size.height)
        }
    }
    private var artwork: some View {
        Group {
            if let data=snapshot.artwork,let image=NSImage(data:data) { Image(nsImage:image).resizable().scaledToFill() }
            else { ZStack { RoundedRectangle(cornerRadius:14).fill(.white.opacity(0.06)); Image(systemName:"music.note").font(.system(size:28)).foregroundStyle(.secondary) } }
        }
    }
    private func control(_ action:String, expanded:Bool, shortcuts:[SpotifyShortcut])->some View {
        let icon: String = ["open":"arrow.up.forward.app","previous track":"backward.end.fill","playpause":snapshot.playing ? "pause.fill":"play.fill","next track":"forward.end.fill","shuffle":"shuffle","repeat":"repeat","volumeDown":"speaker.fill","volumeUp":"speaker.wave.3.fill"][action] ?? "music.note.list"
        let active = (action == "shuffle" && snapshot.shuffle) || (action == "repeat" && snapshot.repeatEnabled)
        let label = ["open":"Apri Spotify","previous track":"Brano precedente","playpause":"Riproduci o pausa","next track":"Brano successivo","shuffle":"Riproduzione casuale","repeat":"Ripetizione","volumeDown":"Abbassa volume","volumeUp":"Alza volume"][action] ?? (Int(action.dropFirst(9)).flatMap { shortcuts.indices.contains($0) ? shortcuts[$0].name:nil } ?? "Apri preferito")
        return Button { self.action(action) } label: {
            if action.hasPrefix("shortcut:"), let i=Int(action.dropFirst(9)), shortcuts.indices.contains(i) {
                Text(shortcuts[i].name).font(.system(size:11,weight:.medium)).lineLimit(1).padding(.horizontal,5).frame(maxWidth:.infinity,maxHeight:.infinity).background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:8))
            } else {
                Image(systemName:icon).font(.system(size:action == "playpause" && expanded ? 23 : 15,weight:.medium)).frame(maxWidth:.infinity,maxHeight:.infinity).foregroundStyle(active ? Color.green : Color.white)
            }
        }.buttonStyle(SpotifyControlStyle(desktopHovered:(appleMusic ? model.appleMusicHover[interactionID] : model.spotifyHover[interactionID]) == action)).disabled(!supports(action)).help(L(action == "open" && appleMusic ? "Apri Musica" : label)).accessibilityLabel(L(action == "open" && appleMusic ? "Apri Musica" : label))
    }
}

struct SpotifyControlStyle: ButtonStyle {
    var desktopHovered:Bool
    @State private var hovered=false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration)->some View {
        configuration.label
            .background(.white.opacity(enabled && (hovered || desktopHovered) ? 0.14:0),in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).stroke(.white.opacity(enabled && (hovered || desktopHovered) ? 0.25:0),lineWidth:1))
            .scaleEffect(configuration.isPressed ? 0.95:1)
            .animation(.easeOut(duration:0.12),value:hovered || desktopHovered)
            .onHover { hovered=$0 }
    }
}
