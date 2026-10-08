import AppKit
import Observation

@MainActor @Observable
final class Model {
    static let shared = Model()
    nonisolated static let systemWidgetIDs = ["clock", "cpu", "memory", "network", "battery", "disk", "uptime", "device"]
    nonisolated static let widgetIDs = ["clock", "cpu", "memory", "network", "battery", "disk", "uptime", "device", "thermal", "apps", "agents", "agentTrend", "agentModels", "agentProjects", "agentActivity", "agentSpending", "agentNow", "agentLive", "spotify"]
    nonisolated static let metricIDs = ["cpu", "memory", "network", "battery", "disk"]
    nonisolated static func localizedName(_ id: String) -> String { L(names[id] ?? id) }
    nonisolated static let names = ["clock":"Orologio", "cpu":"CPU", "memory":"Memoria", "network":"Rete", "battery":"Batteria", "disk":"Disco", "uptime":"Attività", "device":"Nome Mac", "thermal":"Stato termico", "apps":"Applicazioni", "agents":"AI Agents", "agentTrend":"AI · Andamento", "agentModels":"AI · Modelli", "agentProjects":"AI · Progetti", "agentActivity":"AI · Attività", "agentSpending":"AI · Valore API", "agentNow":"AI · Recenti", "agentLive":"AI · Live", "spotify":"Spotify"]
    var prefs: Prefs { didSet {
        if servicesEnabled {
            scheduleSave(); refreshDisplays?()
            if oldValue.agentUsageEnabled != prefs.agentUsageEnabled { configureAgentWatcher(); refreshAgentUsage(force: true) }
            if oldValue.codexAccountEnabled != prefs.codexAccountEnabled { codexAccount = CodexAccountSnapshot(); lastAccount = .distantPast }
            if oldValue.spotifyEnabled != prefs.spotifyEnabled { spotifyDenied = false; lastSpotify = .distantPast; if prefs.spotifyEnabled != true { spotify = SpotifySnapshot() } }
        }
    } }
    var savedPresets: [SavedPreset] = []
    var previousSettings: Prefs?
    var performanceVariant: PerformanceVariant = .full
    var storageMessage: String?
    @ObservationIgnored private var saveTimer: Timer?
    let metrics = MetricReadings()
    var appPresence: [AppPresence] = []
    var agentUsage = AgentUsageSnapshot()
    var liveAgents: [AgentLiveState] = []
    var codexAccount = CodexAccountSnapshot()
    var spotify = SpotifySnapshot()
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
    @ObservationIgnored private var spotifyTask: Task<Void, Never>?
    @ObservationIgnored private var lastLive = Date.distantPast
    @ObservationIgnored private var lastAccount = Date.distantPast
    @ObservationIgnored private var lastSpotify = Date.distantPast
    @ObservationIgnored private var spotifyDenied = false
    func refreshCodexAccount(force: Bool = false) {
        guard prefs.agentUsageEnabled == true, prefs.codexAccountEnabled == true else { return }
        if accountTask != nil { if force { accountDirty = true }; return }
        guard force || Date().timeIntervalSince(lastAccount) > 300 else { return }
        accountDirty = false
        lastAccount = Date()
        var threads: [String] = []
        for event in agentUsage.events.reversed() where event.provider == "Codex" {
            let parts = event.id.split(separator: ":")
            if parts.count == 3, !threads.contains(String(parts[1])) { threads.append(String(parts[1])) }
            if threads.count == 8 { break }
        }
        let executable = prefs.codexExecutable ?? CodexAccountReader.defaultExecutable
        accountTask = Task { [weak self, accountReader, threads] in
            let value = await accountReader.read(executable: executable, threads: threads)
            guard let self else { return }
            if self.prefs.agentUsageEnabled == true && self.prefs.codexAccountEnabled == true { self.codexAccount = value }
            self.accountTask = nil
            if self.accountDirty { self.refreshCodexAccount(force: true) }
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
    func refreshSpotify(retry: Bool = false) {
        if retry { spotifyDenied = false; lastSpotify = .distantPast }
        guard prefs.spotifyEnabled == true, !spotifyDenied, spotifyTask == nil, Date().timeIntervalSince(lastSpotify) > 3 else { return }
        lastSpotify = Date()
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").contains { !$0.isTerminated }
        spotifyTask = Task { [weak self, spotifyReader] in
            let value = await spotifyReader.read(running: running)
            guard let self else { return }
            if self.prefs.spotifyEnabled == true {
                if self.spotify != value { self.spotify = value }
                self.spotifyDenied = value.denied
            }
            self.spotifyTask = nil
        }
    }
    func spotifyCommand(_ command: String) {
        guard prefs.spotifyEnabled == true, spotify.available else { return }
        Task { [weak self, spotifyReader] in
            do { try await spotifyReader.command(command); self?.lastSpotify = .distantPast; self?.refreshSpotify() }
            catch { self?.spotify.error = "Spotify non ha accettato il comando." }
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
    var editing = false { didSet { editChanged?(editing) } }
    var identifyUntil = Date.distantPast
    @ObservationIgnored var refreshDisplays: (() -> Void)?
    @ObservationIgnored var editChanged: ((Bool) -> Void)?
    @ObservationIgnored private var timer: Timer?
    private let sampler = MetricsSampler()
    private let servicesEnabled: Bool
    // Checks use an isolated instance without timers, readers or persisted writes.
    static func isolated(preferences: Prefs = Prefs()) -> Model {
        Model(initialPreferences: preferences, servicesEnabled: false)
    }
    private init(initialPreferences: Prefs? = nil, servicesEnabled: Bool = true) {
        self.servicesEnabled = servicesEnabled
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
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        tick()
    }
    static var preferencesURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/dev.aniello.macsystemwallpaper/native-settings.json")
    }
    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in Task { @MainActor in self?.save() } }
    }
    func save() {
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
        if prefs.agentUsageEnabled == true { refreshAgentUsage(); refreshLive(); refreshCodexAccount() }
        refreshSpotify()
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
        previousSettings = prefs
        prefs = next
        save()
    }
    func apply(_ preset: BuiltInPreset) {
        previousSettings = prefs
        prefs = preset.settings(from: prefs, displayKeys: orderedScreens().map(displayKey), displaySizes: Dictionary(uniqueKeysWithValues: orderedScreens().map { (displayKey($0), $0.frame.size) }))
        save()
    }
    func undoSettings() {
        guard let previous = previousSettings else { return }
        prefs = previous
        previousSettings = nil
        save()
    }
    func savePreset(name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw SettingsError.invalid("Inserisci un nome per il preset.") }
        var next = savedPresets
        next.append(SavedPreset(name: String(name.prefix(80)), archive: try archive()))
        try persistPresets(next)
        savedPresets = next
    }
    func removePreset(_ id: UUID) throws {
        let next = savedPresets.filter { $0.id != id }
        try persistPresets(next)
        savedPresets = next
    }
    private func persistPresets(_ values: [SavedPreset]) throws {
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
    }
    func widgetUnits(_ id: String, axis: String) -> Int {
        if axis == "width" { return prefs.widths[id] ?? (id.hasPrefix("agent") ? 3 : 2) }
        return prefs.heights[id] ?? (id == "agents" ? 2 : 1)
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
    var agentPeriod: String? = nil
    var agentDensity: String? = nil
    var codexAccountEnabled: Bool? = nil
    var codexExecutable: String? = nil
    var spotifyEnabled: Bool? = nil
    var agentUsageEnabled: Bool? = nil
    var appStatusEnabled: Bool? = nil
    var adaptiveAnimation: Bool? = nil
    var widgetTheme: String? = nil
    var wallpaper = "gradient"
    var imagePath: String? = nil
    var syncWallpaper = true
    var displays: [String:DisplayContent] = [:]
    var positions: [String:[String:Point]] = [:]
    var animationPositions: [String:Point] = [:]
    var animationScales: [String:Double]? = nil
    var animationStyle = "jarvis"
    var layers: [Layer] = [Layer(metric: "cpu", color: ColorValue("#82c4ff"))]
    var layout = "free"
    var alertTargets: [String]? = nil
    var alertMetrics: [String]? = nil
    var cellSize = 130.0
    var widths: [String:Int] = ["clock":3,"cpu":2,"memory":2,"network":2,"battery":2,"disk":2,"uptime":2,"device":2]
    var heights: [String:Int] = [:]
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
