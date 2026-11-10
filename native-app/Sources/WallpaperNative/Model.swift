import AppKit
import Observation

@MainActor @Observable
final class Model {
    static let shared = Model()
    nonisolated static let systemWidgetIDs = ["clock", "cpu", "memory", "network", "battery", "disk", "uptime", "device"]
    nonisolated static let widgetIDs = ["clock", "cpu", "memory", "network", "battery", "disk", "uptime", "device", "thermal", "apps", "agents", "agentTrend", "agentModels", "agentProjects", "agentActivity", "agentSpending", "agentNow", "agentLive", "spotify", "appleMusic", "audioMixer"]
    nonisolated static let metricIDs = ["cpu", "memory", "network", "battery", "disk"]
    nonisolated static func localizedName(_ id: String) -> String { L(names[id] ?? id) }
    nonisolated static let names = ["clock":"Orologio", "cpu":"CPU", "memory":"Memoria", "network":"Rete", "battery":"Batteria", "disk":"Disco", "uptime":"Attività", "device":"Nome Mac", "thermal":"Stato termico", "apps":"Applicazioni", "agents":"AI Agents", "agentTrend":"AI · Andamento", "agentModels":"AI · Modelli", "agentProjects":"AI · Progetti", "agentActivity":"AI · Attività", "agentSpending":"AI · Valore API", "agentNow":"AI · Recenti", "agentLive":"AI · Live", "spotify":"Spotify", "appleMusic":"Apple Music", "audioMixer":"Mixer audio"]
    var prefs: Prefs { didSet {
        if !applyingScene { activeSceneID = nil }
        if oldValue.clipboardEnabled != prefs.clipboardEnabled || oldValue.clipboardPaused != prefs.clipboardPaused || oldValue.clipboardLimit != prefs.clipboardLimit || oldValue.clipboardExcludedApps != prefs.clipboardExcludedApps {
            configureClipboard()
        }
        if servicesEnabled {
            scheduleSave(); refreshDisplays?()
            if oldValue.clipboardEnabled != prefs.clipboardEnabled || oldValue.clipboardShortcutEnabled != prefs.clipboardShortcutEnabled { clipboardConfigurationChanged?() }
            if oldValue.agentUsageEnabled != prefs.agentUsageEnabled { configureAgentWatcher(); refreshAgentUsage(force: true) }
            if oldValue.claudeControlEnabled != prefs.claudeControlEnabled { claudeAccount = ClaudeAccountSnapshot(); lastClaudeAccount = .distantPast }
            if oldValue.codexAccountEnabled != prefs.codexAccountEnabled { codexAccount = CodexAccountSnapshot(); lastAccount = .distantPast }
            if oldValue.appleMusicEnabled != prefs.appleMusicEnabled { configureAppleMusic() }
            if oldValue.spotifyEnabled != prefs.spotifyEnabled || oldValue.spotifySource != prefs.spotifySource {
                spotifyRevision += 1; spotifyPlaybackIntent = nil; spotifyDenied = false; lastSpotify = .distantPast
                spotify = SpotifySnapshot(); configureSpotifyObserver()
            }
        }
    } }
    let processMixer = ProcessMixer()
    let clipboard: ClipboardStore
    @ObservationIgnored var clipboardConfigurationChanged: (() -> Void)?
    var savedPresets: [SavedPreset] = []
    var activeSceneID: UUID?
    @ObservationIgnored var applyingScene = false
    var previousSettings: Prefs?
    @ObservationIgnored var previousSettingsAreScene = false
    var performanceVariant: PerformanceVariant = .full
    var storageMessage: String?
    @ObservationIgnored private var saveTimer: Timer?
    let metrics = MetricReadings()
    var appPresence: [AppPresence] = []
    var agentUsage = AgentUsageSnapshot()
    var rankingPages: [String: Int] = [:]
    private func rankingKey(_ id: String, _ display: String) -> String { "\(display):\(id):\(prefs.agentPeriod ?? "all"):\(prefs.agentDensity ?? "compact")" }
    func rankingPage(_ id: String, display: String, total: Int) -> AgentRankingPage {
        let height = orderedScreens().first(where: { displayKey($0) == display }).map { widgetSize(id, screen: $0).height }
        return AgentRankingPage(total: total, size: AgentRankingPage.pageSize(expanded: prefs.agentDensity == "expanded", height: height), requested: rankingPages[rankingKey(id, display)] ?? 0)
    }
    func moveRankingPage(_ id: String, display: String, delta: Int) {
        let summary = agentUsage.periods[prefs.agentPeriod ?? "all"] ?? AgentPeriodSummary()
        let page = rankingPage(id, display: display, total: id == "agentModels" ? summary.models.count : summary.projects.count)
        rankingPages[rankingKey(id, display)] = min(page.count - 1, max(0, page.index + delta))
    }
    var liveAgents: [AgentLiveState] = []
    var codexAccount = CodexAccountSnapshot()
    var claudeAccount = ClaudeAccountSnapshot()
    private let claudeReader = ClaudeAccountReader()
    @ObservationIgnored private var claudeTask: Task<Void, Never>?
    @ObservationIgnored private var lastClaudeAccount = Date.distantPast
    func refreshClaudeAccount(force: Bool = false) {
        guard servicesEnabled, prefs.agentUsageEnabled == true, prefs.claudeControlEnabled == true,
              claudeTask == nil, force || Date().timeIntervalSince(lastClaudeAccount) >= 300 else { return }
        lastClaudeAccount = Date()
        claudeTask = Task { [weak self, claudeReader] in
            let result = await claudeReader.read()
            guard let self else { return }
            if self.prefs.agentUsageEnabled == true, self.prefs.claudeControlEnabled == true {
                self.claudeAccount = .init(quota: result.quota ?? self.claudeAccount.quota, error: result.error)
                struct Status: Encodable { var checked: Date; var quota: AgentQuota?; var error: String? }
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                if let data = try? encoder.encode(Status(checked: Date(), quota: self.claudeAccount.quota, error: result.error)) {
                    try? data.write(to: Self.preferencesURL.deletingLastPathComponent().appending(path: "claude-limit-status.json"), options: .atomic)
                }
            }
            self.claudeTask = nil
        }
    }
    var currentClaudeQuota: AgentQuota? {
        let local = agentUsage.claudeSessions.max(by: { $0.date < $1.date })?.quota
        if prefs.claudeControlEnabled == true { return [claudeAccount.quota, local].compactMap { $0 }.max(by: { $0.date < $1.date }) }
        return [local, agentUsage.claudeDesktop?.quota].compactMap { $0 }.max(by: { $0.date < $1.date })
    }
    var appleMusic = SpotifySnapshot(title: "Apple Music")
    var appleMusicHover: [String: String] = [:]
    @ObservationIgnored var appleMusicObserver: NSObjectProtocol?
    @ObservationIgnored var appleMusicTask: Task<Void, Never>?
    @ObservationIgnored var appleMusicRevision = 0
    @ObservationIgnored var appleMusicDenied = false
    @ObservationIgnored var appleMusicDirty = false
    @ObservationIgnored var appleMusicIntent: SpotifyPlaybackIntent?
    @ObservationIgnored var lastAppleMusic = Date.distantPast
    let appleMusicReader = AppleMusicReader()
    var spotify = SpotifySnapshot()
    var spotifyHover: [String:String] = [:]
    @ObservationIgnored private var spotifyObserver: NSObjectProtocol?
    @ObservationIgnored private var spotifyRevision = 0
    @ObservationIgnored private var spotifyCommandsPending = 0
    @ObservationIgnored private var spotifyPlaybackIntent:SpotifyPlaybackIntent?
    @ObservationIgnored private var spotifySettleTask:Task<Void,Never>?
    @ObservationIgnored private var spotifyPlaybackSerial=0
    @ObservationIgnored private var spotifyDirty = false
    private func configureSpotifyObserver() {
        if let spotifyObserver { DistributedNotificationCenter.default().removeObserver(spotifyObserver); self.spotifyObserver=nil }
        guard prefs.spotifyEnabled == true, prefs.spotifySource != "nowPlaying" else { return }
        spotifyObserver=DistributedNotificationCenter.default().addObserver(forName: prefs.spotifySource == "web" ? SpotifyWebBridge.changed : Notification.Name("com.spotify.client.PlaybackStateChanged"),object:nil,queue:.main) { [weak self] note in
            Task { @MainActor in
                guard let self,self.prefs.spotifyEnabled == true else { return }
                self.spotifyRevision += 1
                self.refreshSpotify(force:true)
            }
        }
    }
    private let liveReader = AgentLiveReader()
    private let agentWatcher = AgentFileWatcher()
    @ObservationIgnored private var usageDirty = false
    @ObservationIgnored private var usageInvalidatePending = false
    private func configureAgentWatcher() {
        agentWatcher.stop()
        if prefs.agentUsageEnabled == true {
            agentWatcher.start { [weak self] in
                guard let self, self.prefs.agentUsageEnabled == true else { return }
                self.usageDirty = true
                self.refreshLive(force: true)
                self.refreshAgentUsage(force: true, invalidateCache: false)
            }
        }
    }
    private let accountReader = CodexAccountReader()
    private let spotifyReader = SpotifyReader()
    @ObservationIgnored private var liveTask: Task<Void, Never>?
    @ObservationIgnored private var accountTask: Task<Void, Never>?
    @ObservationIgnored private var accountDirty = false
    var updatingCounters = false
    var updatingCodexAccount = false
    @ObservationIgnored private var spotifyTask: Task<Void, Never>?
    @ObservationIgnored private var spotifyArtworkTask: Task<Void, Never>?
    @ObservationIgnored private var lastLive = Date.distantPast
    @ObservationIgnored private var lastAccount = Date.distantPast
    @ObservationIgnored private var lastSpotify = Date.distantPast
    @ObservationIgnored private var spotifyDenied = false
    func refreshCodexAccount(force: Bool = false) {
        guard prefs.agentUsageEnabled == true, prefs.codexAccountEnabled == true else { return }
        if accountTask != nil { if force { accountDirty = true }; return }
        guard force || Date().timeIntervalSince(lastAccount) >= CodexAccountReader.refreshInterval(quota: codexAccount.quota) else { return }
        accountDirty = false
        updatingCodexAccount = true
        lastAccount = Date()
        var threads: [String] = []
        for event in agentUsage.events.reversed() where event.provider == "Codex" {
            let parts = event.id.split(separator: ":")
            if parts.count == 3, !threads.contains(String(parts[1])) { threads.append(String(parts[1])) }
            if threads.count == 8 { break }
        }
        let executable = prefs.codexExecutable ?? CodexAccountReader.defaultExecutable
        accountTask = Task { [weak self, accountReader, threads] in
            let value = await accountReader.read(executable: executable, threads: threads, onQuota: { [weak self] quota in
                Task { @MainActor in
                    guard let self, self.prefs.agentUsageEnabled == true, self.prefs.codexAccountEnabled == true else { return }
                    self.codexAccount.quota = quota
                    self.codexAccount.error = nil
                }
            })
            guard let self else { return }
            if self.prefs.agentUsageEnabled == true && self.prefs.codexAccountEnabled == true {
                var result = value
                // A failed read must not discard a valid last measurement.
                if result.quota == nil { result.quota = self.codexAccount.quota }
                self.codexAccount = result
                self.writeAccountStatus()
            }
            self.updatingCodexAccount = false
            self.accountTask = nil
            if self.accountDirty { self.refreshCodexAccount(force: true) }
        }
    }
    private func writeAccountStatus() {
        // Local diagnostics contain only quota readings/errors, never account
        // identifiers, authentication material, conversations or thread costs.
        struct Status: Encodable { var checked: Date; var quota: AgentQuota?; var error: String? }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(Status(checked: Date(), quota: codexAccount.quota, error: codexAccount.error)) {
            try? data.write(to: Self.preferencesURL.deletingLastPathComponent().appending(path: "codex-limit-status.json"), options: .atomic)
        }
    }
    func refreshLive(force: Bool = false) {
        guard prefs.agentUsageEnabled == true, liveTask == nil, force || Date().timeIntervalSince(lastLive) > 3 else { return }
        lastLive = Date()
        liveTask = Task { [weak self, liveReader] in
            let value = await liveReader.read()
            guard let self else { return }
            if self.prefs.agentUsageEnabled == true && self.liveAgents != value { self.liveAgents = value }
            self.liveTask = nil
        }
    }
    func refreshSpotify(retry: Bool = false, force:Bool = false) {
        if retry { spotifyDenied = false; lastSpotify = .distantPast }
        guard prefs.spotifyEnabled == true, !spotifyDenied else { return }
        if spotifyTask != nil { if force || retry { spotifyDirty=true }; return }
        guard force || retry || Date().timeIntervalSince(lastSpotify)>3 else { return }
        spotifyDirty=false
        let revision=spotifyRevision
        lastSpotify = Date()
        let source = prefs.spotifySource
        let running = source != "web" && source != "nowPlaying" && NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").contains { !$0.isTerminated }
        spotifyTask = Task { [weak self, spotifyReader] in
            var value = await spotifyReader.read(source: source, running: running, includeArtwork: false)
            guard let self else { return }
            if self.prefs.spotifyEnabled == true, revision == self.spotifyRevision, self.spotifyCommandsPending == 0 {
                if let intent=self.spotifyPlaybackIntent {
                    value.playing=intent.reconcile(value)
                    if Date() >= intent.deadline || value.trackID != intent.trackID || !value.available { self.spotifyPlaybackIntent=nil }
                }
                if self.spotify != value { self.spotify = value }
                self.spotifyDenied = value.denied
            }
            if value.available, value.artwork == nil, self.spotifyArtworkTask == nil, self.prefs.spotifyEnabled == true, revision == self.spotifyRevision {
                self.spotifyArtworkTask=Task { [weak self,spotifyReader] in
                    let complete = await spotifyReader.read(source: source, running: running, includeArtwork: true)
                    guard let self else { return }
                    if self.prefs.spotifyEnabled == true, self.prefs.spotifySource == source, self.spotify.trackID == complete.trackID, self.spotify.title == complete.title { self.spotify.artwork=complete.artwork }
                    self.spotifyArtworkTask=nil
                    if revision != self.spotifyRevision { self.refreshSpotify(force:true) }
                }
            }
            self.spotifyTask = nil
            if self.spotifyDirty { self.refreshSpotify(force:true) }
        }
    }
    func openSpotifyWeb(_ url: URL = URL(string: "https://open.spotify.com/")!) {
        guard servicesEnabled else { return }
        guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
            spotify.error = "Installa Google Chrome per usare Spotify Web."; return
        }
        NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            if error != nil { Task { @MainActor in self?.spotify.error = "Impossibile aprire Spotify." } }
        }
    }
    func spotifySupports(_ action: String) -> Bool {
        if action == "open" { return prefs.spotifySource != "nowPlaying" }
        if action.hasPrefix("shortcut:") { return true }
        return spotify.available && (spotify.supportedCommands?.contains(action) ?? true)
    }
    func openSpotify() {
        guard servicesEnabled else { return }
        if prefs.spotifySource == "nowPlaying" { return }
        if prefs.spotifySource == "web" { openSpotifyWeb(); return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else {
            spotify.error = "Spotify non è installato sul Mac."
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if error != nil { self.spotify.error = "Impossibile aprire Spotify." }
                else { self.refreshSpotify(retry: true) }
            }
        }
    }
    func spotifyAction(_ action: String) {
        guard servicesEnabled else { return }
        guard prefs.spotifyEnabled == true else { return }
        if action == "open" { openSpotify(); return }
        if action.hasPrefix("shortcut:"), let index = Int(action.dropFirst(9)), let shortcuts = prefs.spotifyShortcuts, shortcuts.indices.contains(index), let url = SpotifyShortcut.uri(shortcuts[index].link) {
            if ["web", "nowPlaying"].contains(prefs.spotifySource ?? ""), let webURL = SpotifyShortcut.webURL(shortcuts[index].link) { openSpotifyWeb(webURL) }
            else if !NSWorkspace.shared.open(url) { spotify.error = "Impossibile aprire Spotify." }
            return
        }
        spotifyCommand(action)
    }
    func setSpotifyVolume(_ value: Int) async throws {
        guard servicesEnabled, prefs.spotifyEnabled == true, spotifySupports("volumeUp"),
              prefs.spotifySource != "web", prefs.spotifySource != "nowPlaying",
              NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").contains(where: { !$0.isTerminated }) else { return }
        spotifyRevision += 1
        spotifyCommandsPending += 1
        defer { spotifyCommandsPending -= 1; refreshSpotify(force: true) }
        try await spotifyReader.setVolume(value)
    }
    func spotifyCommand(_ command: String) {
        guard servicesEnabled else { return }
        guard prefs.spotifyEnabled == true, spotifySupports(command) else { return }
        let source = prefs.spotifySource
        let webSession = spotify.webSession
        spotifyRevision += 1
        spotify.predict(command)
        let delivered = command == "playpause" ? (spotify.playing ? "play":"pause") : command
        if command == "playpause" {
            spotifyPlaybackSerial += 1
            spotifyPlaybackIntent=SpotifyPlaybackIntent(playing:spotify.playing,trackID:spotify.trackID,deadline:Date().addingTimeInterval(1.5))
            spotifySettleTask?.cancel()
        }
        let serial=spotifyPlaybackSerial
        spotifyCommandsPending += 1
        Task { [weak self, spotifyReader] in
            do {
                if source == "nowPlaying" { try await spotifyReader.commandNowPlaying(delivered) }
                else if source == "web" { try SpotifyWebBridge.send(delivered, session: webSession) }
                else { try await spotifyReader.command(delivered) }
            }
            catch {
                if command == "playpause", self?.spotifyPlaybackSerial == serial { self?.spotifyPlaybackIntent=nil }
                if self?.prefs.spotifySource == source {
                    self?.spotify.error = source == "nowPlaying" ? "Comando multimediale non disponibile." : "Spotify non ha accettato il comando."
                }
            }
            self?.spotifyCommandsPending -= 1
            self?.refreshSpotify(force:true)
            if command == "playpause", let self, self.spotifyPlaybackSerial == serial {
                self.spotifySettleTask=Task { [weak self] in
                    do {
                        try await Task.sleep(for:.milliseconds(150))
                        self?.refreshSpotify(force:true)
                        try await Task.sleep(for:.milliseconds(1400))
                        self?.refreshSpotify(force:true)
                    } catch { }
                }
            }
        }
    }
    private let usageReader = AgentUsageReader()
    @ObservationIgnored private var usageTask: Task<Void, Never>?
    @ObservationIgnored private var lastUsageScan = Date.distantPast
    func refreshAgentUsage(force: Bool = false, invalidateCache: Bool = true) {
        guard prefs.agentUsageEnabled == true else {
            usageTask?.cancel(); usageTask = nil; agentUsage = AgentUsageSnapshot(); liveAgents = []; codexAccount = CodexAccountSnapshot(); lastUsageScan = .distantPast
            Task { await usageReader.clear() }
            return
        }
        if usageTask != nil { if force { usageDirty = true; usageInvalidatePending = usageInvalidatePending || invalidateCache }; return }
        guard force || Date().timeIntervalSince(lastUsageScan) >= 30 else { return }
        let clearCache = force && (invalidateCache || usageInvalidatePending)
        usageDirty = false
        usageInvalidatePending = false
        updatingCounters = true
        lastUsageScan = Date()
        usageTask = Task { [weak self, usageReader] in
            if clearCache { await usageReader.clear() }
            let result = await usageReader.scan()
            guard !Task.isCancelled, let self else { return }
            await self.liveReader.seed(result.codexActivity)
            if self.prefs.agentUsageEnabled == true { self.agentUsage = result }
            self.usageTask = nil
            self.updatingCounters = false
            if self.usageDirty { self.refreshAgentUsage(force: true, invalidateCache: self.usageInvalidatePending) }
        }
    }
    private let cpuHistory = MetricHistory()
    private let memoryHistory = MetricHistory()
    func history(for metric: String) -> [Double] {
        switch metric { case "cpu": return cpuHistory.values; case "memory": return memoryHistory.values; default: return [] }
    }
    var editing = false { didSet { if oldValue != editing { editChanged?(editing) } } }
    var identifyUntil = Date.distantPast
    @ObservationIgnored var refreshDisplays: (() -> Void)?
    @ObservationIgnored var editChanged: ((Bool) -> Void)?
    @ObservationIgnored private var timer: Timer?
    private let sampler = MetricsSampler()
    let servicesEnabled: Bool
    // Checks use an isolated instance without timers, readers or persisted writes.
    static func isolated(preferences: Prefs = Prefs(), clipboardPasteboard: NSPasteboard = .general) -> Model {
        Model(initialPreferences: preferences, servicesEnabled: false, clipboardPasteboard: clipboardPasteboard)
    }
    private init(initialPreferences: Prefs? = nil, servicesEnabled: Bool = true, clipboardPasteboard: NSPasteboard = .general) {
        self.servicesEnabled = servicesEnabled
        self.clipboard = ClipboardStore(url: servicesEnabled ? ClipboardStore.fileURL : nil, pasteboard: clipboardPasteboard)
        let url = Self.preferencesURL
        if let initialPreferences { prefs = initialPreferences }
        else if let data = try? Data(contentsOf: url), let loaded = try? JSONDecoder().decode(Prefs.self, from: data) { prefs = loaded }
        else if let data = try? Data(contentsOf: Self.backupURL), let loaded = try? JSONDecoder().decode(Prefs.self, from: data) {
            prefs = loaded
            storageMessage = "Ripristinata l'ultima copia valida delle impostazioni."
        } else {
            prefs = LegacyMigration.load() ?? Prefs()
            if FileManager.default.fileExists(atPath: url.path) { storageMessage = "Il file delle impostazioni non è leggibile. Sono state caricate le impostazioni disponibili." }
        }
        guard servicesEnabled else { return }
        if prefs.animationStyle == "wave" { prefs.animationStyle = "jarvis" }
        if let data = try? Data(contentsOf: Self.presetsURL), let saved = try? JSONDecoder().decode([SavedPreset].self, from: data) { savedPresets = saved }
        migrateDisplays()
        configureAgentWatcher()
        configureSpotifyObserver()
        configureAppleMusic()
        configureClipboard()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        tick()
    }
    func configureClipboard() {
        clipboard.configure(enabled: prefs.clipboardEnabled == true, paused: prefs.clipboardPaused == true,
            limit: prefs.clipboardLimit ?? 100, exclusions: prefs.clipboardExcludedApps ?? [])
    }
    static var preferencesURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/dev.aniello.macsystemwallpaper/native-settings.json")
    }
    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in Task { @MainActor in self?.save() } }
    }
    func save() {
        guard servicesEnabled else { return }
        let url = Self.preferencesURL
        saveTimer?.invalidate()
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let old = try? Data(contentsOf: url), (try? JSONDecoder().decode(Prefs.self, from: old)) != nil {
                try old.write(to: Self.backupURL, options: .atomic)
            }
            try JSONEncoder().encode(prefs).write(to: url, options: .atomic)
        } catch { storageMessage = LF("Impossibile salvare le impostazioni: \(error.localizedDescription)") }
    }
    func tick() {
        let sample = sampler.sample()
        applySample(sample)
        let presence = prefs.appStatusEnabled == true ? AppIntegrations.sample() : []
        if appPresence != presence { appPresence = presence }
        if prefs.agentUsageEnabled == true { refreshAgentUsage(); refreshLive(); refreshCodexAccount(); refreshClaudeAccount() }
        refreshSpotify()
        refreshAppleMusic()
        clipboard.sample()
        if !processMixer.selected.isEmpty { processMixer.refresh() }
    }
    func applySample(_ sample: Metrics) {
        metrics.update(sample)
        cpuHistory.append(sample.cpu)
        memoryHistory.append(sample.memory)
    }
    func displayKey(_ screen: NSScreen) -> String {
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return String(id)
    }
    func displayNumber(_ screen: NSScreen) -> String {
        String((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0)
    }
    func migrateDisplays() {
        var next = prefs
        var changed = false
        for screen in NSScreen.screens {
            let key = displayKey(screen), legacy = displayNumber(screen)
            if key != legacy && next.displays[key] == nil, let content = next.displays[legacy] {
                next.displays[key] = content
                next.positions[key] = next.positions[legacy]
                if let sizes = next.widgetSizes?[legacy] { next.widgetSizes?[key] = sizes }
                next.animationPositions[key] = next.animationPositions[legacy]
                next.animationScales = next.animationScales ?? [:]
                let legacyScale = next.animationScales?[legacy]
                next.animationScales?[key] = legacyScale
                changed = true
            }
        }
        if changed { prefs = next }
    }
    func resumeSampling() {
        sampler.reset()
        cpuHistory.reset()
        memoryHistory.reset()
        tick()
    }
    static var backupURL: URL { preferencesURL.deletingLastPathComponent().appending(path: "native-settings.backup.json") }
    static var presetsURL: URL { preferencesURL.deletingLastPathComponent().appending(path: "presets.json") }
    func archive(portable: Bool = false) throws -> SettingsArchive {
        var result = SettingsArchive(displayOrder: orderedScreens().map(displayKey), settings: prefs)
        if portable && prefs.wallpaper == "image", let path = prefs.imagePath {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard data.count <= 25_000_000 else { throw SettingsError.invalid("Lo sfondo supera 25 MB. Scegli un'immagine più piccola per esportarlo.") }
            result.imageData = data
        }
        return try result.validated()
    }
    func apply(_ archive: SettingsArchive) throws {
        let checked = try archive.validated()
        var next = checked.mapped(to: orderedScreens().map(displayKey))
        if let data = checked.imageData {
            let folder = Self.preferencesURL.deletingLastPathComponent().appending(path: "wallpapers")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appending(path: "imported-\(UUID().uuidString).image")
            try data.write(to: file, options: .atomic)
            next.imagePath = file.path
        }
        if next.wallpaper == "image", next.imagePath == nil || !FileManager.default.fileExists(atPath: next.imagePath!) {
            throw SettingsError.invalid("L'immagine dello sfondo non è disponibile. Esporta includendo l'immagine dal Mac di origine.")
        }
        previousSettingsAreScene = false
        previousSettings = prefs
        prefs = next
        save()
    }
    func apply(_ preset: BuiltInPreset) {
        previousSettingsAreScene = false
        previousSettings = prefs
        prefs = preset.settings(from: prefs, displayKeys: orderedScreens().map(displayKey), displaySizes: Dictionary(uniqueKeysWithValues: orderedScreens().map { (displayKey($0), $0.frame.size) }))
        save()
    }
    func undoSettings() {
        guard let previous = previousSettings else { return }
        prefs = previousSettingsAreScene ? SceneSettings.applying(previous, to: prefs) : previous
        previousSettings = nil
        previousSettingsAreScene = false
        save()
    }
    func savePreset(name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw SettingsError.invalid("Inserisci un nome per la scena.") }
        var next = savedPresets
        next.append(SavedPreset(name: String(name.prefix(80)), archive: try archive()))
        try persistPresets(next)
        savedPresets = next
        activeSceneID = next.last?.id
    }
    func removePreset(_ id: UUID) throws {
        let next = savedPresets.filter { $0.id != id }
        try persistPresets(next)
        savedPresets = next
        if activeSceneID == id { activeSceneID = nil }
    }
    func persistPresets(_ values: [SavedPreset]) throws {
        guard servicesEnabled else { return }
        try FileManager.default.createDirectory(at: Self.presetsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(values).write(to: Self.presetsURL, options: .atomic)
    }
    func exportSettings(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(archive(portable: true)).write(to: url, options: .atomic)
    }
    func importSettings(from url: URL) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 35_000_000 else { throw SettingsError.invalid("File troppo grande: massimo 35 MB.") }
        let archive = try JSONDecoder().decode(SettingsArchive.self, from: Data(contentsOf: url))
        try apply(archive)
    }
    func content(_ screen: NSScreen) -> DisplayContent { prefs.displays[displayKey(screen)] ?? DisplayContent() }
    func setContent(_ screen: NSScreen, _ content: DisplayContent) { prefs.displays[displayKey(screen)] = content }
    func position(_ widget: String, _ screen: NSScreen) -> Point { prefs.positions[displayKey(screen)]?[widget] ?? Prefs.defaults[widget] ?? Point(x: 50, y: 50) }
    func setPosition(_ widget: String, _ screen: NSScreen, _ point: Point) {
        prefs.positions[displayKey(screen), default: [:]][widget] = Point(x: min(100, max(0, point.x)), y: min(100, max(0, point.y)))
    }
    func animationPosition(_ screen: NSScreen) -> Point { prefs.animationPositions[displayKey(screen)] ?? Point(x: 50, y: 50) }
    func setAnimationPosition(_ screen: NSScreen, _ point: Point) { prefs.animationPositions[displayKey(screen)] = Point(x: min(100, max(0, point.x)), y: min(100, max(0, point.y))) }
    func animationScale(_ screen: NSScreen) -> Double { prefs.animationScales?[displayKey(screen)] ?? 1 }
    func setAnimationScale(_ screen: NSScreen, _ scale: Double) {
        var scales = prefs.animationScales ?? [:]
        scales[displayKey(screen)] = min(1.8, max(0.5, scale))
        prefs.animationScales = scales
    }
    func maximumUnits(axis: String) -> Int {
        let lengths = NSScreen.screens.map { axis == "width" ? $0.frame.width : $0.frame.height }
        return max(1, Int((lengths.max() ?? (prefs.cellSize * 10)) / prefs.cellSize))
    }
    func refreshCounters() {
        refreshAgentUsage(force: true)
        refreshLive(force: true)
        refreshCodexAccount(force: true)
        refreshClaudeAccount(force: true)
    }
    func widgetUnits(_ id: String, axis: String) -> Int {
        if axis == "width" { return prefs.widths[id] ?? (id.hasPrefix("agent") || id == "audioMixer" ? 3 : 2) }
        return prefs.heights[id] ?? (id == "agents" ? 2 : 1)
    }
    func musicWidgetHeight(_ id: String) -> Double {
        let expanded = (id == "appleMusic" ? prefs.appleMusicDisplay : prefs.spotifyDisplay) == "expanded"
        let shortcuts = id == "spotify" ? prefs.spotifyShortcuts?.count ?? 0 : 0
        return SpotifyLayout.minimumHeight(expanded: expanded, shortcuts: shortcuts) + 32
    }

    func setMusicDisplay(_ id: String, _ display: String) {
        var next = prefs
        if id == "appleMusic" { next.appleMusicDisplay = display }
        else { next.spotifyDisplay = display }
        next.heights.removeValue(forKey: id)
        for key in (next.widgetSizes ?? [:]).keys {
            next.widgetSizes?[key]?[id]?.automaticHeight = true
        }
        prefs = next
    }

    func widgetSize(_ id: String, screen: NSScreen) -> WidgetSize {
        let custom = prefs.widgetSizes?[displayKey(screen)]?[id]
        let defaultSize = WidgetSize(width: Double(widgetUnits(id, axis: "width")) * prefs.cellSize,
                                     height: Double(widgetUnits(id, axis: "height")) * prefs.cellSize)
        var proposed = custom ?? defaultSize
        if ["appleMusic", "spotify"].contains(id),
           custom?.automaticHeight == true || (custom == nil && prefs.heights[id] == nil) {
            let expanded = (id == "appleMusic" ? prefs.appleMusicDisplay : prefs.spotifyDisplay) == "expanded"
            proposed.height = musicWidgetHeight(id)
            proposed.width = max(proposed.width, expanded ? 272 : 152)
            if prefs.layout == "grid" {
                let cell = prefs.cellSize
                proposed.height = ceil(proposed.height / cell) * cell
                proposed.width = ceil(proposed.width / cell) * cell
            }
        }
        if id == "audioMixer", custom == nil, prefs.heights[id] == nil {
            let height = MixerWidget.preferredHeight(count: processMixer.selected.count)
            proposed.height = prefs.layout == "grid" ? ceil(height / prefs.cellSize) * prefs.cellSize : height
        }
        return WidgetSizing.constrained(proposed, available: WidgetSize(width: screen.frame.width, height: screen.frame.height),
                                        cell: prefs.layout == "grid" ? prefs.cellSize : nil)
    }
    func resizeWidget(_ id: String, screen: NSScreen, origin: Point, size: WidgetSize) {
        let bounded = WidgetSizing.constrained(size,
            available: WidgetSize(width: screen.frame.width * (1 - origin.x / 100), height: screen.frame.height * (1 - origin.y / 100)),
            cell: prefs.layout == "grid" ? prefs.cellSize : nil)
        var next = prefs
        var sizes = next.widgetSizes ?? [:]
        sizes[displayKey(screen), default: [:]][id] = bounded
        next.widgetSizes = sizes
        next.positions[displayKey(screen), default: [:]][id] = origin
        prefs = next
    }
    func setWidgetUnits(_ id: String, axis: String, units: Int) {
        var next = prefs
        if axis == "width" { next.widths[id] = units } else { next.heights[id] = units }
        for key in (next.widgetSizes ?? [:]).keys {
            guard var size = next.widgetSizes?[key]?[id] else { continue }
            if axis == "width" { size.width = Double(units) * next.cellSize } else { size.height = Double(units) * next.cellSize; size.automaticHeight = nil }
            next.widgetSizes?[key]?[id] = size
        }
        prefs = next
    }
    func severity(_ metric: String, target: String = "widgets") -> String {
        guard prefs.alerts, (prefs.alertTargets ?? ["widgets", "animation"]).contains(target), (prefs.alertMetrics ?? Self.metricIDs + ["thermal"]).contains(metric) else { return "normal" }
        if metric == "thermal" {
            switch metrics.thermal { case .critical: return "critical"; case .serious: return "warning"; default: return "normal" }
        }
        if metric == "battery" && metrics.battery == nil { return "normal" }
        let value = metrics.percentage(metric)
        let threshold = prefs.thresholds[metric] ?? Threshold(warning: 75, critical: 90)
        if metric == "battery" { return value <= threshold.critical ? "critical" : value <= threshold.warning ? "warning" : "normal" }
        return value >= threshold.critical ? "critical" : value >= threshold.warning ? "warning" : "normal"
    }
    func metricColor(_ metric: String, base: ColorValue, target: String = "widgets") -> ColorValue {
        switch severity(metric, target: target) { case "critical": return prefs.criticalColor; case "warning": return prefs.warningColor; default: return base }
    }
}

struct Point: Codable, Equatable { var x: Double; var y: Double }
struct Threshold: Codable { var warning: Double; var critical: Double }
struct ColorValue: Codable, Equatable {
    var hex: String
    init(_ hex: String) { self.hex = hex }
    var color: NSColor { NSColor(hex: hex) }
}
struct Layer: Codable, Identifiable { var metric: String; var color: ColorValue; var id: String { metric } }
struct DisplayContent: Codable {
    var widgets: [String] = ["clock", "cpu", "memory", "network"]
    var animation = true
}
struct WidgetDisplay: Codable { var chart = "bar"; var density = "compact" }
struct Prefs: Codable {
    static let defaults: [String:Point] = [
        "clock": Point(x: 6,y: 18), "device": Point(x: 6,y: 40),
        "cpu": Point(x: 79,y: 14), "memory": Point(x: 79,y: 27),
        "network": Point(x: 79,y: 40), "battery": Point(x: 79,y: 53),
        "disk": Point(x: 79,y: 66), "uptime": Point(x: 79,y: 79)
    ]
    var clipboardEnabled: Bool? = nil
    var clipboardPaused: Bool? = nil
    var clipboardLimit: Int? = nil
    var clipboardShortcutEnabled: Bool? = nil
    var clipboardExcludedApps: [String]? = nil
    var sceneAutomationEnabled: Bool? = nil
    var agentPeriod: String? = nil
    var agentDensity: String? = nil
    var claudeControlEnabled: Bool? = nil
    var codexAccountEnabled: Bool? = nil
    var codexExecutable: String? = nil
    var appleMusicEnabled: Bool? = nil
    var appleMusicDisplay: String? = nil
    var spotifyEnabled: Bool? = nil
    var spotifySource: String? = nil
    var spotifyDisplay: String? = nil
    var spotifyShortcuts: [SpotifyShortcut]? = nil
    var agentUsageEnabled: Bool? = nil
    var appStatusEnabled: Bool? = nil
    var adaptiveAnimation: Bool? = nil
    var widgetTheme: String? = nil
    var wallpaper = "system"
    var imagePath: String? = nil
    var syncWallpaper = false
    var displays: [String:DisplayContent] = [:]
    var positions: [String:[String:Point]] = [:]
    var animationPositions: [String:Point] = [:]
    var animationScales: [String:Double]? = nil
    var animationStyle = "jarvis"
    var animationBoxes: [String: [String]]? = nil
    var layers: [Layer] = [Layer(metric: "cpu", color: ColorValue("#82c4ff"))]
    var layout = "free"
    var alertTargets: [String]? = nil
    var alertMetrics: [String]? = nil
    var cellSize = 130.0
    var widths: [String:Int] = ["clock":3,"cpu":2,"memory":2,"network":2,"battery":2,"disk":2,"uptime":2,"device":2]
    var heights: [String:Int] = [:]
    var widgetSizes: [String: [String: WidgetSize]]? = nil
    var cpuDisplay = WidgetDisplay()
    var memoryDisplay = WidgetDisplay()
    var alerts = true
    var warningColor = ColorValue("#ffbd59")
    var criticalColor = ColorValue("#ff5b68")
    var thresholds: [String:Threshold] = [
        "cpu":Threshold(warning:70,critical:90), "memory":Threshold(warning:75,critical:90),
        "disk":Threshold(warning:85,critical:95), "battery":Threshold(warning:20,critical:10),
        "network":Threshold(warning:10,critical:18)
    ]
    var networkScaleMBps = 20.0
}

extension NSColor {
    convenience init(hex: String) {
        let text = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(text, radix: 16) ?? 0x82c4ff
        self.init(calibratedRed: CGFloat((value >> 16) & 255)/255, green: CGFloat((value >> 8) & 255)/255, blue: CGFloat(value & 255)/255, alpha: 1)
    }
}

@MainActor func orderedScreens() -> [NSScreen] {
    guard let primary = NSScreen.screens.first else { return [] }
    return [primary] + NSScreen.screens.dropFirst().sorted {
        $0.frame.minX == $1.frame.minX ? $0.frame.minY < $1.frame.minY : $0.frame.minX < $1.frame.minX
    }
}
