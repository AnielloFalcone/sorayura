import AppKit

/// Scenes own presentation; account opt-ins, warning rules and system sync stay global.
enum SceneSettings {
    static func applying(_ scene: Prefs, to current: Prefs) -> Prefs {
        var next = current
        next.widgetTheme = scene.widgetTheme
        next.wallpaper = scene.wallpaper; next.imagePath = scene.imagePath
        next.displays = scene.displays; next.positions = scene.positions
        next.animationPositions = scene.animationPositions; next.animationScales = scene.animationScales
        next.animationStyle = scene.animationStyle; next.animationBoxes = scene.animationBoxes; next.layers = scene.layers
        next.layout = scene.layout; next.cellSize = scene.cellSize
        next.widths = scene.widths; next.heights = scene.heights; next.widgetSizes = scene.widgetSizes
        next.cpuDisplay = scene.cpuDisplay; next.memoryDisplay = scene.memoryDisplay
        next.agentPeriod = scene.agentPeriod; next.agentDensity = scene.agentDensity
        next.spotifyDisplay = scene.spotifyDisplay; next.appleMusicDisplay = scene.appleMusicDisplay
        next.networkScaleMBps = scene.networkScaleMBps
        return next
    }
    static func automaticScene(in scenes: [SavedPreset], applicationID: String?, enabled: Bool, editing: Bool) -> SavedPreset? {
        guard enabled, !editing, let applicationID,
              applicationID != Bundle.main.bundleIdentifier else { return nil }
        return scenes.first { $0.applicationBundleID == applicationID }
    }
}

extension Model {
    func activateScene(_ scene: SavedPreset) throws {
        let checked = try scene.archive.validated()
        let appearance = SceneSettings.applying(checked.settings, to: prefs)
        applyingScene = true
        defer { applyingScene = false }
        try apply(SettingsArchive(displayOrder: checked.displayOrder, settings: appearance, imageData: checked.imageData))
        previousSettingsAreScene = true
        activeSceneID = scene.id
    }
    func activateScene(for applicationID: String?) {
        guard let scene = SceneSettings.automaticScene(in: savedPresets, applicationID: applicationID,
            enabled: prefs.sceneAutomationEnabled == true, editing: editing), activeSceneID != scene.id else { return }
        do { try activateScene(scene) }
        catch { storageMessage = error.localizedDescription }
    }
    func renameScene(_ id: UUID, name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw SettingsError.invalid("Inserisci un nome per la scena.") }
        var next = savedPresets
        guard let index = next.firstIndex(where: { $0.id == id }) else { return }
        next[index].name = String(name.prefix(80))
        try persistPresets(next); savedPresets = next
    }
    func updateScene(_ id: UUID) throws {
        var next = savedPresets
        guard let index = next.firstIndex(where: { $0.id == id }) else { return }
        next[index].archive = try archive()
        try persistPresets(next); savedPresets = next; activeSceneID = id
    }
    func setSceneApplication(_ id: UUID, bundleID: String?, name: String? = nil) throws {
        if let bundleID {
            guard !bundleID.isEmpty, bundleID.count <= 255,
                  bundleID.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_")).contains($0) }),
                  bundleID != Bundle.main.bundleIdentifier else { throw SettingsError.invalid("Scegli un’app diversa da Sorayura.") }
        }
        var next = savedPresets
        guard let index = next.firstIndex(where: { $0.id == id }) else { return }
        // One foreground app selects one scene; moving its rule removes the old match.
        if let bundleID {
            for other in next.indices where next[other].applicationBundleID == bundleID {
                next[other].applicationBundleID = nil; next[other].applicationName = nil
            }
        }
        next[index].applicationBundleID = bundleID
        next[index].applicationName = bundleID == nil ? nil : String((name ?? bundleID!).prefix(80))
        try persistPresets(next); savedPresets = next
    }
}
