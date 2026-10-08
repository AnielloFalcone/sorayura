import SwiftUI

private struct WallpaperGlassDisabledKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var wallpaperGlassDisabled: Bool {
        get { self[WallpaperGlassDisabledKey.self] }
        set { self[WallpaperGlassDisabledKey.self] = newValue }
    }
}

private struct WallpaperGlass: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.wallpaperGlassDisabled) private var disabled
    @ViewBuilder func body(content: Content) -> some View {
        if disabled {
            content.background(Color(red: 0.05, green: 0.09, blue: 0.16).opacity(0.62),
                               in: RoundedRectangle(cornerRadius: cornerRadius))
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

extension View {
    func wallpaperGlass(cornerRadius: CGFloat = 16) -> some View {
        modifier(WallpaperGlass(cornerRadius: cornerRadius))
    }
}
