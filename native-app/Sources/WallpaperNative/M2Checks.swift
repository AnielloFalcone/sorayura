import Foundation
import CryptoKit
import AppKit
import MapKit

@MainActor enum M2Checks {
    static func run() throws {
        func check(_ passed: Bool, _ message: String) throws {
            if !passed { throw SettingsError.invalid(message) }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let month = CalendarMonth(date: date, calendar: calendar)!
        let size = CGSize(width: 210, height: 220)
        try check(CalendarWidget.day(at: CGPoint(x: 15, y: 80), size: size, month: month) == date &&
                  CalendarWidget.day(at: CGPoint(x: 15, y: 50), size: size, month: month) == nil,
                  "Calendar hit testing must include empty days and exclude padding cells")
        let december = Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 31))!
        let january = Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 1))!
        let agenda = CalendarAgenda(defaults: nil)
        agenda.setDisplay(.month)
        agenda.moveMonth(by: 1, displayID: "external", now: december)
        try check(agenda.visibleMonth(displayID: "external", now: december)?.interval.start == january &&
                  agenda.visibleMonth(displayID: "laptop", now: december)?.interval.contains(december) == true,
                  "Calendar month navigation must cross years and stay local to the display")
        let firstDayCell = agenda.visibleMonth(displayID: "external", now: december)!.days.firstIndex(of: january)!
        let firstDayPoint = CGPoint(x: CGFloat(firstDayCell) * 30 + 15, y: 41)
        try check(CalendarWidget.clickableDay(at: firstDayPoint, size: size, agenda: agenda, displayID: "external") == january,
                  "Calendar click and hover must target the month shown by the widget")
        agenda.moveMonth(by: 0, displayID: "external", now: december)
        try check(agenda.visibleMonth(displayID: "external", now: december)?.interval.contains(december) == true &&
                  CalendarWidget.monthNavigation(at: CGPoint(x: 140, y: 10), size: size) == -1 &&
                  CalendarWidget.monthNavigation(at: CGPoint(x: 180, y: 10), size: size) == 0 &&
                  CalendarWidget.monthNavigation(at: CGPoint(x: 200, y: 10), size: size) == 1 &&
                  CalendarWidget.monthNavigation(at: CGPoint(x: 200, y: 30), size: size) == nil,
                  "Calendar month controls must work only in the header and return to the current month")
        let topRight = CGPoint(x: 200, y: 10)
        try check(CalendarWidget.addButtonContains(topRight, size: size, display: .list, showingDay: false) &&
                  CalendarWidget.addButtonContains(topRight, size: size, display: .month, showingDay: true) &&
                  !CalendarWidget.addButtonContains(topRight, size: size, display: .month, showingDay: false),
                  "Calendar add button must match the agenda and day detail headers")
        try check(CalendarWidget.rowIndex(at: 26, top: 25, height: 33, spacing: 5) == 0 &&
                  CalendarWidget.rowIndex(at: 59, top: 25, height: 33, spacing: 5) == nil &&
                  CalendarWidget.rowIndex(at: 63, top: 25, height: 33, spacing: 5) == 1,
                  "Calendar editing must target the clicked row and ignore the gap")
        let externalScreen = CGRect(x: -1920, y: 100, width: 1920, height: 1000)
        let editorFrame = CalendarAgenda.centeredFrame(CGSize(width: 476, height: 378), in: externalScreen)
        try check(externalScreen.contains(editorFrame) && editorFrame.midX == externalScreen.midX,
                  "Calendar editor must use the widget display even with negative desktop coordinates")
        let evening = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: date)!
        let midnight = calendar.date(byAdding: .day, value: 1, to: date)!
        let dayRange = CalendarAgenda.convertedEventRange(start: evening, end: midnight, allDay: true, calendar: calendar)
        try check(dayRange.start == date && dayRange.end == date, "Midnight end must not add another all-day date")
        let timedRange = CalendarAgenda.convertedEventRange(start: dayRange.start, end: dayRange.end, allDay: false, calendar: calendar)
        try check(calendar.component(.hour, from: timedRange.start) == 9 &&
                  timedRange.end.timeIntervalSince(timedRange.start) == 3600,
                  "Returning to a timed event must provide a valid one-hour range")
        let region = CalendarPlaceSearch.nearbyRegion(around: CLLocationCoordinate2D(latitude: 45.4642, longitude: 9.1909))
        try check(region.center.latitude == 45.46 && region.center.longitude == 9.19,
                  "Nearby Maps suggestions must use an approximate location")
        let locationField = CGRect(x: 12, y: 80, width: 360, height: 40)
        let suggestionsBelow = CalendarEventEditor.suggestionsFrame(below: locationField, viewportHeight: 340)
        let suggestionsAbove = CalendarEventEditor.suggestionsFrame(below: locationField, viewportHeight: 150)
        try check(suggestionsBelow?.minY == 126 && suggestionsBelow?.width == 360 &&
                  suggestionsAbove?.maxY == 74 &&
                  CalendarEventEditor.suggestionsFrame(below: locationField.offsetBy(dx: 0, dy: -130), viewportHeight: 340) == nil,
                  "Calendar location suggestions must follow the field and fit the visible form")
        try check(AgentRankingPage.pageSize(expanded: false, height: 120) == 1 && AgentRankingPage.pageSize(expanded: true, height: 240) == 6, "Pagination hides rows in a small widget")
        for total in [0, 1, 3, 4, 7, 40] {
            var visited: [Int] = []
            let first = AgentRankingPage(total: total, size: 3, requested: 0)
            for index in 0..<first.count { visited += AgentRankingPage(total: total, size: 3, requested: index).range }
            try check(visited == Array(0..<total), "Rankings pagination loses or duplicates entries")
            try check(AgentRankingPage(total: total, size: 3, requested: 999).index == first.count - 1, "Rankings page is not clamped after refresh")
        }
        try check(AgentRankingPage.action(at: CGPoint(x: 25, y: 58), width: 260) == -1 && AgentRankingPage.action(at: CGPoint(x: 232, y: 58), width: 260) == 1, "Ranking button hit areas differ from their layout")
        let paginationModel = Model.isolated()
        var summary = AgentPeriodSummary(); summary.models = (0..<10).map { ("model-\($0)", Double($0)) }
        paginationModel.agentUsage.periods["all"] = summary
        paginationModel.moveRankingPage("agentModels", display: "a", delta: 1)
        try check(paginationModel.rankingPage("agentModels", display: "a", total: 10).index == 1 && paginationModel.rankingPage("agentModels", display: "b", total: 10).index == 0, "Ranking pages leak between monitors")
        var web = SpotifyWebSnapshot(title: "Track", artist: "Artist", album: "", available: true, playing: true, artworkURL: "https://i.scdn.co/image/example", trackID: "/track/example", volume: 50, shuffle: false, repeatEnabled: false, supportedCommands: ["play", "pause"])
        try check(web.valid, "Valid Spotify Web snapshot rejected")
        web.artworkURL = "https://i.scdn.co.evil.test/image"; try check(!web.valid, "Untrusted artwork host accepted")
        web.artworkURL = ""; web.supportedCommands = ["shell"]; try check(!web.valid, "Unknown browser command accepted")
        let systemReading = try JSONDecoder().decode(SystemNowPlaying.Reading.self, from: Data(#"{"title":"Track","artist":"Artist","playing":true,"artwork":"YQ=="}"#.utf8)).snapshot
        try check(systemReading.available && systemReading.playing && systemReading.artwork == Data([97]), "System Now Playing metadata did not decode")
        let systemLayout = SpotifyLayout(size: CGSize(width: 400, height: 400), expanded: true, shortcuts: 0, nowPlaying: true)
        try check(systemLayout.controls.map(\.0) == ["previous track", "playpause", "next track"] && systemLayout.volumeBar == nil,
                  "System Now Playing exposes unsupported controls")
        let mixerSuite = "Sorayura.M2Checks.\(UUID().uuidString)"
        let mixerDefaults = UserDefaults(suiteName: mixerSuite)!
        defer { mixerDefaults.removePersistentDomain(forName: mixerSuite) }
        let mixer = ProcessMixer(defaults: mixerDefaults)
        let mixerSize = CGSize(width: 300, height: MixerWidget.preferredHeight(count: 2) - 32)
        try check(MixerWidget.preferredHeight(count: 0) < MixerWidget.preferredHeight(count: 2), "Empty mixer is not compact")
        var openedMixerSettings = false
        MixerWidget.click(CGPoint(x: 290, y: 10), size: mixerSize, mixer: mixer) { openedMixerSettings = true }
        try check(openedMixerSettings, "Mixer process picker is not reachable from its header")
        let app = AudioProcess(id: 100, pid: 100, name: "Test", selectionID: "dev.sorayura.test")
        mixer.updateAvailable([app])
        mixer.select(app, true)
        try check(MixerWidget.beginSlider(CGPoint(x: 100, y: 80), size: mixerSize, mixer: mixer) != nil &&
                  MixerWidget.beginSlider(CGPoint(x: 290, y: 80), size: mixerSize, mixer: mixer) == nil,
                  "Mixer slider and mute hit areas overlap")
        mixer.updateAvailable([])
        try check(mixer.selected.isEmpty, "Mixer still shows a closed app")
        let reopened = ProcessMixer(defaults: mixerDefaults)
        let restartedApp = AudioProcess(id: 101, pid: 101, name: "Test", selectionID: app.selectionID)
        reopened.updateAvailable([restartedApp])
        try check(reopened.selected == [restartedApp], "Mixer selection did not survive relaunch and PID change")
        reopened.select(restartedApp, false)
        let deselected = ProcessMixer(defaults: mixerDefaults)
        deselected.updateAvailable([restartedApp])
        try check(deselected.selected.isEmpty, "Mixer restored an explicitly deselected app")
        let resources = Bundle.main.resourceURL!
        let extensionManifest = try JSONSerialization.jsonObject(with: Data(contentsOf: resources.appending(path: "SpotifyWebExtension/manifest.json"))) as! [String: Any]
        let extensionKey = Data(base64Encoded: extensionManifest["key"] as! String)!
        let alphabet = Array("abcdefghijklmnop")
        let extensionID = SHA256.hash(data: extensionKey).prefix(16).flatMap { [alphabet[Int($0 >> 4)], alphabet[Int($0 & 15)]] }
        try check(String(extensionID) == SpotifyWebBridge.extensionID && FileManager.default.isExecutableFile(atPath: resources.appending(path: "spotify-web-host").path), "Packaged Chrome extension identity/host does not match the native bridge")
        let extensionIcons = extensionManifest["icons"] as? [String: String] ?? [:]
        try check(extensionIcons.count == 4 && extensionIcons.values.allSatisfy { FileManager.default.fileExists(atPath: resources.appending(path: "SpotifyWebExtension/" + $0).path) }, "Chrome extension icon assets are missing from the companion")
        let framed = SpotifyNativeHost.frame(Data("{}".utf8))
        let framing = Pipe(); framing.fileHandleForWriting.write(framed); try framing.fileHandleForWriting.close()
        try check(try SpotifyNativeHost.readMessage(framing.fileHandleForReading) == Data("{}".utf8), "Native messaging framing corrupted")
        try check(try SpotifyNativeHost.readMessage(framing.fileHandleForReading) == nil, "Native message EOF not recognized")
        for invalid in [Data([0, 0, 0, 0]), Data([1, 0, 1, 0]), Data([8, 0, 0, 0, 123])] {
            let pipe = Pipe(); pipe.fileHandleForWriting.write(invalid); try pipe.fileHandleForWriting.close()
            var rejected = false
            do { _ = try SpotifyNativeHost.readMessage(pipe.fileHandleForReading) } catch { rejected = true }
            try check(rejected, "Invalid native message accepted")
        }
        try check(SpotifyShortcut.webURL("spotify:track:0123456789ABCDEFGHIJKL")?.absoluteString == "https://open.spotify.com/track/0123456789ABCDEFGHIJKL", "Web shortcut left the browser")
        let codex = """
        {"type":"session_meta","payload":{"id":"session","cwd":"/tmp/project"},"timestamp":"2026-10-01T10:00:00Z"}
        {"type":"turn_context","payload":{"model":"example-model"},"timestamp":"2026-10-01T10:00:00Z"}
        {"timestamp":"2026-10-01T10:00:01.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100,"cached_input_tokens":20,"output_tokens":10}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":30,"resets_at":1790900000,"window_minutes":300}}}}
        {"timestamp":"2026-10-01T10:00:02Z","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100,"cached_input_tokens":20,"output_tokens":10}}}}
        broken-json
        {"timestamp":"2026-10-01T10:00:03Z","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":160,"cached_input_tokens":50,"output_tokens":15}}}}
        """
        let result = AgentUsageReader.parse(Data(codex.utf8), provider: "Codex", source: "fixture")
        try check(result.events.count == 2 && result.tokens == 160, "Repeated cumulative token events were counted twice")
        try check(result.events.reduce(0) { $0 + $1.cached } == 50, "Cached token deltas incorrect")
        try check(result.events.last?.project == "project" && result.events.last?.model == "example-model", "Metadata lost")
        try check(result.codexQuota?.session?.used == 30, "Quota missing")
        let temporary = FileManager.default.temporaryDirectory.appending(path: "wallpaper-m2-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try (Data(repeating: 65, count: 1_100_000) + Data("\n".utf8) + Data(codex.utf8)).write(to: temporary)
        let streamed = AgentUsageReader.parseLines(try UsageLines(temporary), provider: "Codex", source: "fixture")
        try check(streamed.tokens == result.tokens && streamed.events.count == result.events.count, "Streaming lost usage after oversized lines")
        let claude = """
        {"type":"assistant","cwd":"/tmp/work","timestamp":"2026-10-01T10:00:01Z","message":{"id":"message","model":"example-claude","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":20,"cache_creation_input_tokens":30}}}
        """
        let usage = AgentUsageReader.parse(Data(claude.utf8), provider: "Claude", source: "fixture")
        try check(usage.tokens == 65 && usage.events.first?.cached == 20, "Claude cache accounting incorrect")
        try check(AgentUsageReader.deduplicate(usage.events + usage.events).count == 1, "Claude duplicated message counted twice")
        try check(usage.codexQuota == nil, "Claude quota fabricated")
        try check(ThermalPresentation.frames(.critical, lowPower: false, adaptive: true) == 10, "Critical energy policy incorrect")
        try check(ThermalPresentation.frames(.nominal, lowPower: true, adaptive: true) == 20, "Low power energy policy incorrect")
        try check(ThermalPresentation.frames(.serious, lowPower: true, adaptive: false) == 30, "Energy override ignored")
        let bridgeInput = Data("{\"session_id\":\"sample\",\"model\":{\"display_name\":\"Claude\"},\"workspace\":{\"current_dir\":\"/tmp/project\"},\"cost\":{\"total_cost_usd\":1.25},\"rate_limits\":{\"five_hour\":{\"used_percentage\":23.5,\"resets_at\":1790900000}}}".utf8)
        let bridge = try ClaudeBridge.decode(bridgeInput)
        try check(bridge.apiValue == 1.25 && bridge.quota.session?.used == 23.5 && bridge.quota.week == nil, "Claude statusline counters incorrect")
        try check(bridge.session != "sample" && bridge.session.count == 64, "Session identifier not anonymized")
        let roundtrip = try JSONDecoder().decode(ClaudeSessionSnapshot.self, from: JSONEncoder().encode(bridge))
        try check(roundtrip.project == "project", "Claude snapshot persistence incorrect")
        let testFolder = FileManager.default.temporaryDirectory.appending(path: "wallpaper-claude-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testFolder) }
        let watchedFolder = testFolder.appending(path: ".codex/sessions")
        try FileManager.default.createDirectory(at: watchedFolder, withIntermediateDirectories: true)
        let watcher = AgentFileWatcher()
        var notifications = 0
        watcher.start(home: testFolder) { notifications += 1 }
        let watchedFile = watchedFolder.appending(path: "new-session.jsonl")
        try Data("first\n".utf8).write(to: watchedFile)
        let deadline = Date().addingTimeInterval(5)
        while notifications == 0 && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        try check(notifications > 0, "Native watcher missed a newly created session")
        notifications = 0
        try Data("second\n".utf8).write(to: watchedFile, options: .atomic)
        let secondDeadline = Date().addingTimeInterval(5)
        while notifications == 0 && Date() < secondDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        try check(notifications > 0, "Native watcher missed atomic replacement")
        watcher.stop()
        let testSettings = testFolder.appending(path: "settings.json"), testBackup = testFolder.appending(path: "backup.json")
        let initial: [String: Any] = ["theme":"dark", "statusLine":["type":"command", "command":"cat", "padding":2]]
        try JSONSerialization.data(withJSONObject: initial).write(to: testSettings)
        try ClaudeBridgeInstaller.install(settingsURL: testSettings, backupURL: testBackup, executableURL: URL(fileURLWithPath: "/tmp/an app's path"))
        var modified = try ClaudeBridgeInstaller.current(at: testSettings)
        let legacy = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Developer/macbook-system-wallpaper-m0/native-app/build/Mac System Wallpaper.app/Contents/MacOS/MacSystemWallpaper")
        let renamed = URL(fileURLWithPath: "/Applications/Sorayura.app/Contents/MacOS/Sorayura")
        try ClaudeBridgeInstaller.uninstall(settingsURL: testSettings, backupURL: testBackup)
        try ClaudeBridgeInstaller.install(settingsURL: testSettings, backupURL: testBackup, executableURL: legacy)
        modified = ClaudeHooksInstaller.changed(try ClaudeBridgeInstaller.current(at: testSettings), command: ClaudeBridgeInstaller.quote(legacy.path) + " --claude-event")
        try JSONSerialization.data(withJSONObject: modified).write(to: testSettings)
        try BrandMigration.relocate(settingsURL: testSettings, backupURL: testBackup, executableURL: renamed)
        let relocated = try ClaudeBridgeInstaller.current(at: testSettings)
        try check((relocated["statusLine"] as? [String: Any])?["command"] as? String == ClaudeBridgeInstaller.quote(renamed.path) + " --claude-statusline --forward-statusline 'cat'", "Brand migration loses forwarded status line")
        let encodedRelocated = try JSONSerialization.data(withJSONObject: relocated, options: .sortedKeys)
        try check(!String(decoding: encodedRelocated, as: UTF8.self).contains("MacSystemWallpaper"), "Brand migration leaves legacy hook paths")
        try BrandMigration.relocate(settingsURL: testSettings, backupURL: testBackup, executableURL: renamed)
        try check(try JSONSerialization.data(withJSONObject: ClaudeBridgeInstaller.current(at: testSettings), options: .sortedKeys) == encodedRelocated, "Brand migration is not idempotent")
        modified = ClaudeHooksInstaller.changed(relocated, command: nil)
        modified["theme"] = "light"
        try JSONSerialization.data(withJSONObject: modified).write(to: testSettings)
        try ClaudeBridgeInstaller.uninstall(settingsURL: testSettings, backupURL: testBackup)
        let restoredLine = try ClaudeBridgeInstaller.current(at: testSettings)
        try check(restoredLine["theme"] as? String == "light" && NSDictionary(dictionary: restoredLine["statusLine"] as! [String: Any]).isEqual(to: initial["statusLine"] as! [String: Any]), "Statusline restore loses unrelated settings")
        let forwarded = testFolder.appending(path: "forward.json")
        FileManager.default.createFile(atPath: forwarded.path, contents: nil)
        let writer = try FileHandle(forWritingTo: forwarded)
        ClaudeBridge.forward(bridgeInput, command: "cat", output: writer)
        try writer.close()
        try check((try Data(contentsOf: forwarded)) == bridgeInput, "Existing statusline stdin not preserved")
        let now = Date()
        let desktopFixture = try JSONSerialization.data(withJSONObject: ["version":2, "samples":[["t":now.timeIntervalSince1970 * 1000, "u":["fh":25,"sd":62,"so":40,"sn":17]]]])
        let desktop = ClaudeDesktopLimits.decode(desktopFixture, now: now)
        try check(desktop?.quota.session?.used == 25 && desktop?.quota.week?.used == 62 && desktop?.opus?.used == 40 && desktop?.quota.session?.reset == nil, "Desktop Claude limits or unknown reset incorrect")
        try check(ClaudeDesktopLimits.decode(desktopFixture, now: now.addingTimeInterval(301 * 60))?.quota.session == nil, "Expired desktop session remains visible")
        try check(ClaudeDesktopLimits.decode(Data("{\"version\":99,\"samples\":[]}".utf8)) == nil, "Unknown desktop schema accepted")
        let musicDescriptor = NSAppleEventDescriptor.list()
        for (index, value) in [NSAppleEventDescriptor(string: "Fixture"), .init(string: "Artist"), .init(string: "Album"), .init(boolean: true), .init(int32: 130), .init(boolean: false), .init(boolean: true), .init(string: "ID")].enumerated() {
            musicDescriptor.insert(value, at: index + 1)
        }
        let music = AppleMusicReader.snapshot(musicDescriptor)
        try check(music.title == "Fixture" && music.artist == "Artist" && music.playing && music.volume == 100 && music.repeatEnabled && music.trackID == "ID", "Apple Music descriptor decoding changed")
        try check(!AppleMusicReader.snapshot(.list()).available, "Empty Apple Music library creates a track")
        try check(AppleMusicReader.commandSource("do shell script") == nil && AppleMusicReader.commandSource("play") == "play", "Apple Music command allowlist accepts arbitrary scripts")
        var musicPrefs = Prefs(); musicPrefs.appleMusicEnabled = true; musicPrefs.appleMusicDisplay = "expanded"
        let musicRoundtrip = try JSONDecoder().decode(Prefs.self, from: JSONEncoder().encode(musicPrefs))
        try musicRoundtrip.validate()
        try check(musicRoundtrip.appleMusicEnabled == true && musicRoundtrip.appleMusicDisplay == "expanded" && Prefs().appleMusicEnabled != true && Model.widgetIDs.contains("appleMusic"), "Music preferences or widget registration changed")
        for command in ["play", "pause", "next track", "previous track", "shuffle", "repeat", "volumeUp", "volumeDown"] {
            var parseError: NSDictionary?
            let script = NSAppleScript(source: "tell application id \"com.apple.Music\"\n" + AppleMusicReader.commandSource(command)! + "\nend tell")!
            try check(script.compileAndReturnError(&parseError), "Apple Music command does not compile: " + command)
        }
        var predicted=SpotifySnapshot(playing:true,available:true,volume:100)
        predicted.predict("playpause");predicted.predict("shuffle");predicted.predict("repeat");predicted.predict("volumeUp")
        try check(!predicted.playing && predicted.shuffle && predicted.repeatEnabled && predicted.volume == 100,"Spotify feedback or volume clamp incorrect")
        predicted.volume=0;predicted.predict("volumeDown");try check(predicted.volume == 0,"Negative Spotify volume feedback")
        let transitionTime=Date()
        let pauseIntent=SpotifyPlaybackIntent(playing:false,trackID:"track",deadline:transitionTime.addingTimeInterval(1.5))
        for playing in [true,false,true,false] {
            let delayed=SpotifySnapshot(playing:playing,available:true,trackID:"track")
            try check(!pauseIntent.reconcile(delayed,now:transitionTime.addingTimeInterval(0.2)),"Late playback sample reverses pause feedback")
        }
        let resumed=SpotifySnapshot(playing:true,available:true,trackID:"track")
        try check(pauseIntent.reconcile(resumed,now:transitionTime.addingTimeInterval(2)),"Playback intent hides later external changes")
        try check(pauseIntent.reconcile(SpotifySnapshot(playing:true,available:true,trackID:"new"),now:transitionTime),"Playback intent overrides a different track")
        let centered=SpotifyLayout(size:CGSize(width:600,height:400),expanded:true,shortcuts:0)
        let buttons=centered.controls.filter {["shuffle","previous track","playpause","next track","repeat"].contains($0.0)}
        try check((buttons.first!.1.minX+buttons.last!.1.maxX)/2 == 300 && centered.volumeBar?.midY == centered.controls.first(where:{$0.0 == "volumeDown"})?.1.midY,"Spotify transport or volume alignment incorrect")
        let spotifyID = "0123456789ABCDEFGHIJKL"
        try check(SpotifyShortcut.uri("https://open.spotify.com/playlist/" + spotifyID + "?si=example")?.absoluteString == "spotify:playlist:" + spotifyID, "Shared playlist link not normalized")
        try check(SpotifyShortcut.uri("https://open.spotify.com/intl-es/album/" + spotifyID) != nil, "Localized album link rejected")
        for invalid in ["https://evil.test/playlist/" + spotifyID, "spotify:playlist:bad", "file:///tmp/test", "https://open.spotify.com/playlist/" + spotifyID + "/extra", "spotify:playlist:\" & do shell script \"bad"] {
            try check(SpotifyShortcut.uri(invalid) == nil, "Unsafe shortcut accepted")
        }
        for (size, expanded, count) in [(CGSize(width:400,height:350),true,3),(CGSize(width:260,height:160),true,6),(CGSize(width:400,height:160),false,0),(CGSize(width:48,height:48),true,6),(CGSize(width:400,height:350),true,6)] {
            let layout = SpotifyLayout(size:size,expanded:expanded,shortcuts:count)
            let bounds = CGRect(origin:.zero,size:size)
            for (action,rect) in layout.controls {
                try check(bounds.contains(rect) && layout.action(at:CGPoint(x:rect.midX,y:rect.midY),available:true) == action, "Spotify controls are out of bounds or not clickable")
            }
            for (index,item) in layout.controls.enumerated() {
                for other in layout.controls.dropFirst(index+1) { try check(!item.1.intersects(other.1), "Spotify controls overlap") }
            }
        }
        var legacyClaudeJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Prefs())) as! [String: Any]
        legacyClaudeJSON["claudeAccountEnabled"] = true
        let legacyClaudePreferences = try JSONDecoder().decode(Prefs.self, from: JSONSerialization.data(withJSONObject: legacyClaudeJSON))
        let encodedPreferences = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyClaudePreferences)) as! [String: Any]
        try check(encodedPreferences["claudeAccountEnabled"] == nil, "Removed Claude CLI polling survives settings migration")
        try check(ClaudeAccountReader.isRecent(now.addingTimeInterval(-180), now: now), "Valid Claude cache timestamp rejected during its write throttle")
        try check(!ClaudeAccountReader.isRecent(now.addingTimeInterval(-600), now: now) && !ClaudeAccountReader.isRecent(now.addingTimeInterval(60), now: now), "Stale or future Claude timestamp accepted")
        let controlResult: [String: Any] = ["rate_limits_available":true, "rate_limits":["five_hour":["utilization":28, "resets_at":NSNull()], "seven_day":["utilization":64, "resets_at":"2099-01-01T00:00:00.123456+00:00"]]]
        let controlQuota = ClaudeAccountReader.quota(controlResult, observed: now)
        try check(controlQuota?.session?.used == 28 && controlQuota?.session?.reset == nil && controlQuota?.week?.used == 64, "Structured Claude quota parsing failed")
        for invalid: Any in [true, -1, 101, Double.infinity, "25"] {
            try check(ClaudeAccountReader.quota(["rate_limits_available":true,"rate_limits":["five_hour":["utilization":invalid]]], observed:now) == nil, "Invalid Claude percentage accepted")
        }
        try check(ClaudeAccountReader.quota(["rate_limits_available":true,"rate_limits":["five_hour":["utilization":10,"resets_at":"2000-01-01T00:00:00Z"]]], observed:now) == nil, "Expired Claude limit accepted")
        try check(ClaudeAccountReader.arguments.contains("--no-session-persistence") && ClaudeAccountReader.arguments.contains("--print"), "Claude quota reader could save an interactive session")
        let expiredDesktop = ClaudeDesktopLimits.decode(desktopFixture, now: now.addingTimeInterval(8 * 86400))
        try check(expiredDesktop?.quota.date == desktop?.quota.date && expiredDesktop?.quota.session == nil && expiredDesktop?.quota.week == nil, "Expired history loses its last observation or invents current limits")
        let historyWatchFile = testFolder.appending(path: "history.json")
        try Data("{}".utf8).write(to: historyWatchFile, options: .atomic)
        try check(AgentFileWatcher.watchDirectory(for: historyWatchFile.path) == testFolder.path, "History watch uses a file instead of its atomic-write parent")
        let running = try ClaudeActivity.decode(Data("{\"session_id\":\"sample\",\"cwd\":\"/tmp/work\",\"hook_event_name\":\"UserPromptSubmit\"}".utf8), now: now)
        try check(running.displayState(now: now) == "Al lavoro" && running.displayState(now: now.addingTimeInterval(301)) == "Da verificare", "Stale live state remains running")
        let waiting = try ClaudeActivity.decode(Data("{\"session_id\":\"sample\",\"hook_event_name\":\"PermissionRequest\"}".utf8))
        try check(waiting.state == "waiting", "Permission request not tracked")
        let original: [String: Any] = ["theme":"dark", "hooks":["Stop":[["matcher":"", "hooks":[["type":"command", "command":"echo original"]]]]]]
        let installed = ClaudeHooksInstaller.changed(original, command: "wallpaper --claude-event")
        let reinstalled = ClaudeHooksInstaller.changed(installed, command: "wallpaper --claude-event")
        let restored = ClaudeHooksInstaller.changed(reinstalled, command: nil)
        try check(NSDictionary(dictionary: restored).isEqual(to: original), "Hook installation loses existing settings or duplicates hooks")
        let started = "{\"timestamp\":\"2026-10-01T10:00:00Z\",\"payload\":{\"type\":\"task_started\"}}"
        let stopped = "{\"timestamp\":\"2026-10-01T10:00:01Z\",\"payload\":{\"type\":\"task_complete\"}}"
        let active = AgentLiveReader.parse(Data(started.utf8), id: "test", project: "work")
        let seeded = AgentUsageReader.parse(Data((started + "\n" + codex).utf8), provider: "Codex", source: "/tmp/test.jsonl").codexActivity.first
        try check(seeded?.state == "running" && seeded?.file == "/tmp/test.jsonl", "Full history does not seed long-running tasks")
        let heartbeat = "{\"timestamp\":\"2026-10-01T10:00:05Z\",\"payload\":{\"type\":\"token_count\"}}"
        try check(AgentLiveReader.parse(Data(heartbeat.utf8), id: "test", project: "work", previous: seeded)?.state == "running", "Tail heartbeat loses seeded task status")
        try check(active?.state == "running", "Codex start ignored")
        try check(AgentLiveReader.parse(Data(stopped.utf8), id: "test", project: "work", previous: active)?.state == "idle", "Codex completion ignored")
        let account: [String: Any] = ["rateLimitsByLimitId":["codex":["primary":["usedPercent":44, "resetsAt":1790900000, "windowDurationMins":300]]]]
        try check(CodexAccountReader.quota(account)?.session?.used == 44, "Official account quota schema ignored")
        let validQuota = AgentQuota(date: now, plan: nil, session: AgentLimit(used: 20, reset: now.addingTimeInterval(60), minutes: 300), week: nil)
        let expiredQuota = AgentQuota(date: now, plan: nil, session: AgentLimit(used: 20, reset: now.addingTimeInterval(-1), minutes: 300), week: nil)
        try check(CodexAccountReader.refreshInterval(quota: validQuota, now: now) == 300 && CodexAccountReader.refreshInterval(quota: expiredQuota, now: now) == 60 && CodexAccountReader.refreshInterval(quota: nil, now: now) == 60, "Expired or missing account limits do not refresh promptly")
        let ai = BuiltInPreset.all.first { $0.id == "ai" }!.settings(from: Prefs(), displayKeys: ["laptop", "external"], displaySizes: ["laptop": NSSize(width: 1440, height: 900), "external": NSSize(width: 2560, height: 1440)])
        try ai.validate()
        try check(ai.agentUsageEnabled != true && ai.spotifyEnabled != true && ai.codexAccountEnabled != true, "Preset enables network or permissions unexpectedly")
        for point in ai.positions["laptop"]!.values { try check(point.y < 90, "AI preset overflows laptop") }
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Prefs())) as! [String: Any]
        json.removeValue(forKey: "agentUsageEnabled"); json.removeValue(forKey: "appStatusEnabled"); json.removeValue(forKey: "adaptiveAnimation")
        let old = try JSONDecoder().decode(Prefs.self, from: JSONSerialization.data(withJSONObject: json))
        try check(old.agentUsageEnabled != true && old.appStatusEnabled != true, "Existing settings enable integrations unexpectedly")
        try old.validate()
        print("M2 checks passed: token deltas, cache, quota, malformed records, thermal policy, old settings")
    }
}
