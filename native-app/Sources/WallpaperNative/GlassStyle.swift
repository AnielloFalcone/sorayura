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

/// Apply glass to the complete content, rather than an empty background shape.
struct DesktopWidgetSurface: ViewModifier {
    var theme: String
    var transparent: Bool
    @Environment(\.wallpaperGlassDisabled) private var disabled
    @ViewBuilder func body(content: Content) -> some View {
        if transparent { content }
        else if theme == "glass" && !disabled {
            if #available(macOS 26, *) {
                content.glassEffect(.clear, in: RoundedRectangle(cornerRadius: 18))
            } else {
                content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        } else {
            content.background(Color(red: 0.05, green: 0.09, blue: 0.16).opacity(theme == "cyber" ? 0.85 : 0.62),
                               in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

struct DesktopGlassGroup: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26, *) { GlassEffectContainer(spacing: 0) { content } }
        else { content }
    }
}
