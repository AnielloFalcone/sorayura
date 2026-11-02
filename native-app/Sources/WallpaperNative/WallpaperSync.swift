import Foundation

/// Layout/Space recovery must not overwrite a wallpaper changed outside Sorayura.
struct WallpaperSync {
    private struct Configuration: Equatable {
        var style: String
        var image: String?
        var enabled: Bool
        var size: CGSize
        var scale: Double
    }
    private var applied: [String: Configuration] = [:]

    mutating func retainDisplays(_ ids: Set<String>) { applied = applied.filter { ids.contains($0.key) } }
    mutating func needsApply(id: String, prefs: Prefs, size: CGSize, scale: Double) -> Bool {
        let next = Configuration(style: prefs.wallpaper, image: prefs.imagePath, enabled: prefs.syncWallpaper, size: size, scale: scale)
        let changed = applied[id] != next
        applied[id] = next
        return changed && next.enabled && next.style != "system"
    }
}
