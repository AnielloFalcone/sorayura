import AppKit

actor AppleMusicReader {
    private var artworkID = ""
    private var artwork: Data?
    private func script(_ source: String) throws -> NSAppleEventDescriptor {
        var error: NSDictionary?
        let result = NSAppleScript(source: "with timeout of 3 seconds\ntell application id \"com.apple.Music\"\n" + source + "\nend tell\nend timeout")?.executeAndReturnError(&error)
        if let error { throw NSError(domain: "AppleMusic", code: (error[NSAppleScript.errorNumber] as? Int) ?? -1) }
        guard let result else { throw NSError(domain: "AppleMusic", code: -1) }
        return result
    }
    func read(running: Bool) -> SpotifySnapshot {
        guard running else { return SpotifySnapshot(title: "Apri Musica") }
        do {
            let value = try script("""
                if not (exists current track) then return {}
                set t to current track
                return {name of t, artist of t, album of t, (player state is playing), sound volume, shuffle enabled, (song repeat is not off), persistent ID of t}
                """)
            guard value.numberOfItems == 8 else { return SpotifySnapshot(title: "Nessun brano") }
            let id = value.atIndex(8)?.stringValue ?? ""
            if artworkID != id {
                artworkID = id; artwork = nil
                if let data = try? script("if (count of artworks of current track) > 0 then return raw data of artwork 1 of current track").data,
                   data.count < 5_000_000, NSImage(data: data) != nil { artwork = data }
            }
            return Self.snapshot(value, artwork: artwork)
        } catch {
            let denied = (error as NSError).code == -1743
            return SpotifySnapshot(title: "Apple Music", error: denied ? "Consenti Musica in Privacy e sicurezza → Automazione, poi premi Riprova." : "Musica non risponde. Riprova collegamento.", denied: denied)
        }
    }
    static func snapshot(_ value: NSAppleEventDescriptor, artwork: Data? = nil) -> SpotifySnapshot {
        guard value.numberOfItems == 8 else { return SpotifySnapshot(title: "Nessun brano") }
        return SpotifySnapshot(title: value.atIndex(1)?.stringValue ?? "Nessun brano", artist: value.atIndex(2)?.stringValue ?? "",
                album: value.atIndex(3)?.stringValue ?? "", playing: value.atIndex(4)?.booleanValue ?? false, available: true,
                artwork: artwork, volume: min(100, max(0, Int(value.atIndex(5)?.int32Value ?? 50))),
                shuffle: value.atIndex(6)?.booleanValue ?? false, repeatEnabled: value.atIndex(7)?.booleanValue ?? false, trackID: value.atIndex(8)?.stringValue ?? "")
    }
    static func commandSource(_ name: String) -> String? {
        switch name {
        case "play", "pause", "previous track", "next track": return name
        case "shuffle": return "set shuffle enabled to not shuffle enabled"
        case "repeat": return "if song repeat is off then\nset song repeat to all\nelse\nset song repeat to off\nend if"
        case "volumeDown": return "set v to sound volume\nif v < 10 then\nset sound volume to 0\nelse\nset sound volume to (v - 10)\nend if"
        case "volumeUp": return "set v to sound volume\nif v > 90 then\nset sound volume to 100\nelse\nset sound volume to (v + 10)\nend if"
        default: return nil
        }
    }
    func setVolume(_ value: Int) throws {
        _ = try script("set sound volume to \(min(100, max(0, value)))")
    }
    func command(_ name: String) throws {
        guard let source = Self.commandSource(name) else { throw SettingsError.invalid("Comando musicale non valido.") }
        _ = try script(source)
    }
}

extension Model {
    func configureAppleMusic() {
        if let appleMusicObserver { DistributedNotificationCenter.default().removeObserver(appleMusicObserver) }
        appleMusicObserver = nil
        appleMusicRevision += 1; appleMusicDenied = false; appleMusicIntent = nil; appleMusic = SpotifySnapshot(title: "Apple Music")
        guard prefs.appleMusicEnabled == true else { return }
        appleMusicObserver = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshAppleMusic(force: true) }
        }
        refreshAppleMusic(force: true)
    }
    func refreshAppleMusic(force: Bool = false, retry: Bool = false) {
        if retry { appleMusicDenied = false }
        guard servicesEnabled, prefs.appleMusicEnabled == true, !appleMusicDenied else { return }
        if appleMusicTask != nil { if force || retry { appleMusicDirty = true }; return }
        guard force || retry || Date().timeIntervalSince(lastAppleMusic) > 3 else { return }
        lastAppleMusic = Date(); appleMusicDirty = false
        let revision = appleMusicRevision
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").contains { !$0.isTerminated }
        appleMusicTask = Task { [weak self, appleMusicReader] in
            var value = await appleMusicReader.read(running: running)
            guard let self else { return }
            if self.prefs.appleMusicEnabled == true, revision == self.appleMusicRevision {
                if let intent = self.appleMusicIntent {
                    value.playing = intent.reconcile(value)
                    if Date() >= intent.deadline || value.trackID != intent.trackID || !value.available { self.appleMusicIntent = nil }
                }
                if self.appleMusic != value { self.appleMusic = value }
                self.appleMusicDenied = value.denied
            }
            self.appleMusicTask = nil
            if self.appleMusicDirty { self.refreshAppleMusic(force: true) }
        }
    }
    func appleMusicSupports(_ action: String) -> Bool { action == "open" || (appleMusic.available && (action == "playpause" || AppleMusicReader.commandSource(action) != nil)) }
    func setAppleMusicVolume(_ value: Int) async throws {
        guard servicesEnabled, prefs.appleMusicEnabled == true, appleMusicSupports("volumeUp"),
              NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").contains(where: { !$0.isTerminated }) else { return }
        appleMusicRevision += 1
        defer { refreshAppleMusic(force: true) }
        try await appleMusicReader.setVolume(value)
    }
    func appleMusicAction(_ action: String) {
        guard servicesEnabled, prefs.appleMusicEnabled == true, appleMusicSupports(action) else { return }
        if action == "open" {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
                Task { @MainActor in
                    if error != nil { self?.appleMusic.error = "Impossibile aprire Musica." }
                    else { self?.refreshAppleMusic(retry: true) }
                }
            }
            return
        }
        appleMusicRevision += 1
        let revision = appleMusicRevision
        appleMusic.predict(action)
        let delivered = action == "playpause" ? (appleMusic.playing ? "play" : "pause") : action
        if action == "playpause" { appleMusicIntent = SpotifyPlaybackIntent(playing: appleMusic.playing, trackID: appleMusic.trackID, deadline: Date().addingTimeInterval(1.5)) }
        Task { [weak self, appleMusicReader] in
            do { try await appleMusicReader.command(delivered) }
            catch {
                if let self, self.appleMusicRevision == revision { self.appleMusicIntent = nil; self.appleMusic.error = "Musica non ha accettato il comando." }
            }
            self?.refreshAppleMusic(force: true)
        }
    }
}
