import AppKit
import SwiftUI
import Observation

@MainActor @Observable final class SettingsNavigation {
    var section = "Preset"
}

/// Keeps only navigation and geometry after close, never the SwiftUI view tree.
@MainActor final class SettingsPresentation: NSObject, NSWindowDelegate {
    private(set) var window: NSWindow?
    let navigation = SettingsNavigation()
    private var savedFrame: NSRect?

    func prepare(model: Model) -> NSWindow {
        if let window { return window }
        let next = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
                            styleMask: [.titled, .closable, .miniaturizable, .resizable],
                            backing: .buffered, defer: false)
        next.minSize = NSSize(width: 860, height: 680)
        next.title = "Sorayura — Impostazioni"
        next.isReleasedWhenClosed = false
        next.delegate = self
        next.contentView = NSHostingView(rootView: SettingsView(navigation: navigation).environment(model))
        if let savedFrame, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(savedFrame) }) {
            next.setFrame(savedFrame, display: false)
        } else {
            next.center()
        }
        window = next
        return next
    }

    func show(model: Model) {
        prepare(model: model).makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        savedFrame = closing.frame
        // Detaching the hosting view ends observations, subscriptions and previews.
        closing.contentView = nil
        closing.delegate = nil
        window = nil
    }
}
