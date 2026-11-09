import AppKit

/// Interactive QA uses a private pasteboard and no user history or preference writes.
@MainActor enum ClipboardPreview {
    static func run() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let board = NSPasteboard.withUniqueName()
        var prefs = Prefs(); prefs.clipboardEnabled = true
        let model = Model.isolated(preferences: prefs, clipboardPasteboard: board)
        model.configureClipboard()
        for text in ["https://github.com/AnielloFalcone/sorayura", "Sample note — local clipboard preview", "git status --short", "Reusable sample text"] {
            board.clearContents(); board.setString(text, forType: .string)
            board.setString("dev.sorayura.preview", forType: .init("org.nspasteboard.source"))
            model.clipboard.sample()
        }
        model.clipboard.toggleFavorite(model.clipboard.entries[1].id)
        let presentation = ClipboardPresentation()
        let shortcut = ClipboardHotKey()
        shortcut.action = { print("Clipboard preview hotkey received"); presentation.show(model: model, settings: {}) }
        let registered = shortcut.configure(enabled: true)
        print("Clipboard preview: private pasteboard; shortcut registered=\(registered)")
        presentation.show(model: model, settings: {})
        application.run()
        shortcut.stop(); board.releaseGlobally()
    }
}
