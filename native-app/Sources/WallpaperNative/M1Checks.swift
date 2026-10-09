import AppKit

@MainActor
enum M1Checks {
    static func run() throws {
        func check(_ passed: Bool, _ message: String) throws {
            if !passed { throw SettingsError.invalid(message) }
        }
        func rejects(_ archive: SettingsArchive) throws {
            do { _ = try archive.validated() }
            catch { return }
            throw SettingsError.invalid("Invalid archive accepted")
        }
        let freeSize = WidgetSizing.constrained(WidgetSize(width: 347.5, height: 219.25), available: WidgetSize(width: 900, height: 700), cell: nil)
        try check(freeSize == WidgetSize(width: 347.5, height: 219.25), "Free resizing lost fractional points")
        let gridSize = WidgetSizing.constrained(freeSize, available: WidgetSize(width: 370, height: 300), cell: 130)
        try check(gridSize == WidgetSize(width: 260, height: 260), "Grid resize exceeded the anchored display bounds")
        let tiny = WidgetSizing.constrained(WidgetSize(width: -500, height: 5000), available: WidgetSize(width: 50, height: 65), cell: 130)
        try check(tiny == WidgetSize(width: 50, height: 65), "Resize did not honor minimum size or small display bounds")
        let base = Prefs()
        try base.validate()
        for preset in BuiltInPreset.all {
            let prefs = preset.settings(from: base, displayKeys: ["laptop", "external"])
            try prefs.validate()
            try check(prefs.displays.count == 2, "Preset missing a display")
            try check(prefs.syncWallpaper == base.syncWallpaper, "Preset changed wallpaper sync")
        }
        let monitoring = BuiltInPreset.all.first { $0.id == "monitoring" }!.settings(from: base, displayKeys: ["a", "b"])
        let archive = SettingsArchive(displayOrder: ["a", "b"], settings: monitoring)
        let data = try JSONEncoder().encode(archive)
        let decoded = try JSONDecoder().decode(SettingsArchive.self, from: data).validated()
        let remapped = decoded.mapped(to: ["new-a", "new-b", "new-c"])
        try check(remapped.displays["new-c"]?.widgets == Model.systemWidgetIDs, "New display mapping failed")
        try check(remapped.positions["new-a"]?["memory"] == monitoring.positions["a"]?["memory"], "Position mapping failed")
        var mixed = archive
        mixed.settings.displays["a"] = DisplayContent(widgets: ["cpu"], animation: false)
        mixed.settings.displays["b"] = DisplayContent(widgets: ["memory"], animation: true)
        let mixedResult = mixed.mapped(to: ["b", "new-display"])
        try check(mixedResult.displays["b"]?.widgets == ["memory"] && mixedResult.displays["new-display"]?.widgets == ["cpu"], "Exact matches consumed twice")
        let small = BuiltInPreset.all.first { $0.id == "monitoring" }!.settings(from: base, displayKeys: ["small"], displaySizes: ["small": NSSize(width: 1440, height: 900)])
        let stack = ["cpu", "network", "battery", "disk", "uptime"]
        for index in 1..<stack.count {
            let previous = stack[index - 1], next = stack[index]
            let units = small.heights[previous] ?? 1
            let bottom = (small.positions["small"]?[previous]?.y ?? 0) / 100 * 900 + Double(units) * 130 + Double(units - 1) * 10
            let top = (small.positions["small"]?[next]?.y ?? 0) / 100 * 900
            try check(top >= bottom, "Preset widgets overlap on a small display")
        }
        var enlarged = archive
        enlarged.settings.cellSize = 80
        enlarged.settings.widths["cpu"] = 8
        enlarged.settings.heights["memory"] = 6
        try enlarged.settings.validate()
        var invalid = archive
        invalid.settings.cellSize = -1
        try rejects(invalid)
        invalid = archive; invalid.version = 99; try rejects(invalid)
        invalid = archive; invalid.settings.widths["cpu"] = 101; try rejects(invalid)
        invalid = archive; invalid.settings.positions["a"]?["cpu"] = Point(x: 101, y: 0); try rejects(invalid)
        invalid = archive; invalid.settings.displays["a"]?.widgets.append("unknown"); try rejects(invalid)
        invalid = archive; invalid.imageData = Data([0, 1, 2]); try rejects(invalid)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let image = bitmap.representation(using: .png, properties: [:])!
        var portable = archive
        portable.imageData = image
        let portableDecoded = try JSONDecoder().decode(SettingsArchive.self, from: JSONEncoder().encode(portable)).validated()
        try check(portableDecoded.imageData == image, "Wallpaper image round trip failed")
        var custom = archive
        custom.settings.widgetSizes = ["a": ["memory": freeSize], "b": ["cpu": WidgetSize(width: 480, height: 260)]]
        let customDecoded = try JSONDecoder().decode(SettingsArchive.self, from: JSONEncoder().encode(custom)).validated()
        let customMapped = customDecoded.mapped(to: ["new-a", "new-b"])
        try check(customMapped.widgetSizes?["new-a"]?["memory"] == freeSize && customMapped.widgetSizes?["new-b"]?["cpu"]?.width == 480, "Custom dimensions lost during archive display mapping")
        for preset in BuiltInPreset.all {
            try check(preset.settings(from: custom.settings, displayKeys: ["a"]).widgetSizes == nil, "Built-in preset retained manual sizes")
        }
        var badSize = custom
        badSize.settings.widgetSizes?["a"]?["memory"]?.width = -5
        try rejects(badSize)
        if let screen = NSScreen.screens.first {
            let isolated = Model.isolated()
            isolated.resizeWidget("cpu", screen: screen, origin: Point(x: 10, y: 10), size: freeSize)
            let screenKey = isolated.displayKey(screen)
            try check(isolated.prefs.widgetSizes?[screenKey]?["cpu"] == freeSize, "Resize did not persist on its display")
            try check(isolated.prefs.widgetSizes?.count == 1, "Resize modified unrelated displays")
            isolated.setWidgetUnits("cpu", axis: "width", units: 3)
            try check(isolated.prefs.widgetSizes?[screenKey]?["cpu"]?.height == freeSize.height && isolated.widgetSize("cpu", screen: screen).width == 390, "Unit picker lost the other custom dimension")
        }
        let sampler = MetricsSampler()
        _ = sampler.sample()
        sampler.reset()
        let resumed = sampler.sample()
        try check(resumed.cpu == 0 && resumed.download == 0 && resumed.upload == 0, "Wake sampling baseline not reset")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as! [String: Any]
        legacy.removeValue(forKey: "widgetTheme")
        legacy.removeValue(forKey: "widgetSizes")
        let legacyDecoded = try JSONDecoder().decode(Prefs.self, from: JSONSerialization.data(withJSONObject: legacy))
        try check(legacyDecoded.widgetTheme == nil && legacyDecoded.widgetSizes == nil, "Old settings no longer decode")
        let original = SavedPreset(name: "Test", archive: archive)
        let restored = try JSONDecoder().decode(SavedPreset.self, from: JSONEncoder().encode(original))
        try check(restored.id == original.id && restored.name == "Test", "Custom preset persistence failed")
        print("M1 checks passed: built-in presets, archive round trip, display mapping, invalid inputs, legacy settings, saved presets")
    }
}
