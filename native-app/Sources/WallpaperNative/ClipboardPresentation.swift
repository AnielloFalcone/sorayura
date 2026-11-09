import AppKit
import CoreGraphics
import SwiftUI
import Carbon

@MainActor final class ClipboardHotKey {
    private var key: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?
    func configure(enabled: Bool) -> Bool {
        stop()
        guard enabled else { return true }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  id.signature == 0x53525943, id.id == 1 else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { Unmanaged<ClipboardHotKey>.fromOpaque(context).takeUnretainedValue().action?() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { stop(); return false }
        let id = EventHotKeyID(signature: 0x53525943, id: 1)
        let registered = RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey), id, GetApplicationEventTarget(), 0, &key)
        if registered != noErr { stop(); return false }
        return true
    }
    func stop() {
        if let key { UnregisterEventHotKey(key); self.key = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }
}

private final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor final class ClipboardPresentation: NSObject, NSWindowDelegate {
    private var window: NSPanel?
    private var previous: NSRunningApplication?
    private var closing = false
    func show(model: Model, settings: @escaping () -> Void) {
        if let window {
            if window.isVisible { close(restore: true); return }
            window.close()
        }
        previous = NSWorkspace.shared.frontmostApplication
        let panel = ClipboardPanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 600), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = true; panel.isFloatingPanel = true
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = L("Clipboard"); panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.appearance = NSAppearance(named: .darkAqua)
        panel.minSize = NSSize(width: 480, height: 420); panel.delegate = self
        let root = ClipboardView(model: model, copy: { [weak self] entry in
            if model.clipboard.copy(entry) { self?.close(restore: true) }
        }, paste: { [weak self] entry in
            self?.pastePlainText(entry, store: model.clipboard)
        }, settings: { [weak self] in self?.close(restore: false); settings() }, dismiss: { [weak self] in self?.close(restore: true) })
        let hosting = NSHostingView(rootView: LocalizedRoot(content: root)); hosting.safeAreaRegions = []
        panel.contentView = hosting
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2, y: visible.midY - panel.frame.height / 2))
        } else { panel.center() }
        window = panel; panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func pastePlainText(_ entry: ClipboardEntry, store: ClipboardStore) {
        guard let target = previous, !target.isTerminated,
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            store.error = "Apri la Clipboard dall’app in cui vuoi incollare."
            return
        }
        guard CGPreflightPostEventAccess() || CGRequestPostEventAccess() else {
            store.error = "Consenti Accessibilità a Sorayura, poi riprova a incollare."
            return
        }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false),
              store.copy(entry, plainText: true) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        let change = NSPasteboard.general.changeCount
        close(restore: true)
        Task { @MainActor in
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(50))
                guard !target.isTerminated, NSPasteboard.general.changeCount == change else { return }
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
                    down.postToPid(target.processIdentifier)
                    up.postToPid(target.processIdentifier)
                    return
                }
            }
        }
    }

    private func close(restore: Bool) {
        guard !closing else { return }
        closing = true
        defer { closing = false }
        let target = previous
        window?.close()
        if restore, target?.processIdentifier != ProcessInfo.processInfo.processIdentifier { target?.activate(options: []) }
    }
    func windowDidResignKey(_ notification: Notification) {
        if let resigning = notification.object as? NSWindow, resigning === window { close(restore: false) }
    }
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        closing.contentView = nil; closing.delegate = nil; window = nil; previous = nil
    }
}

private struct ClipboardView: View {
    @Bindable var model: Model
    let copy: (ClipboardEntry) -> Void
    let paste: (ClipboardEntry) -> Void
    let settings: () -> Void
    let dismiss: () -> Void
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var selection: UUID?
    @FocusState private var searching: Bool
    private var visible: [ClipboardEntry] {
        model.clipboard.entries.filter {
            (!favoritesOnly || $0.favorite) && (query.isEmpty || $0.matches.localizedStandardContains(query))
        }
    }
    private var selectedEntry: ClipboardEntry? { visible.first { $0.id == selection } }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label(L("Clipboard"), systemImage: "doc.on.clipboard").font(.title2.bold())
                Spacer()
                if model.clipboard.enabled {
                    Button { model.prefs.clipboardPaused = !model.clipboard.paused } label: {
                        Image(systemName: model.clipboard.paused ? "play.fill" : "pause.fill")
                    }.help(L(model.clipboard.paused ? "Riprendi raccolta" : "Pausa raccolta"))
                }
                Button(action: settings) { Image(systemName: "gearshape") }.help(L("Impostazioni clipboard"))
            }.padding(.top, 18)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Cerca testo, link o app…"), text: $query).textFieldStyle(.plain).focused($searching)
                    .onSubmit { if let entry = visible.first(where: { $0.id == selection }) { copy(entry) } }
                Toggle(isOn: $favoritesOnly) { Image(systemName: favoritesOnly ? "star.fill" : "star") }
                    .toggleStyle(.button).help(L("Solo preferiti"))
            }.padding(10).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            if !model.clipboard.enabled {
                Text(L("Attiva la cronologia da Impostazioni → Clipboard. I contenuti precedenti restano disponibili.")).font(.caption).foregroundStyle(.secondary)
            } else if model.clipboard.paused {
                Text(L("Raccolta in pausa. Le copie effettuate durante la pausa non vengono recuperate.")).font(.caption).foregroundStyle(.secondary)
            }
            if model.clipboard.accessDenied {
                Text(L("Accesso agli appunti negato da macOS. Controlla le autorizzazioni di Sorayura nelle Impostazioni di Sistema.")).font(.caption).foregroundStyle(.orange)
            }
            if let error = model.clipboard.error { Text(L(error)).font(.caption).foregroundStyle(.orange).lineLimit(3) }
            if visible.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text(L(query.isEmpty ? "Nessun elemento nella clipboard" : "Nessun risultato")).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(visible, selection: $selection) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: entry.isLink ? "link" : "text.alignleft").foregroundStyle(.secondary).frame(width: 20)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(String(entry.text.prefix(300))).lineLimit(3).font(.system(size: 12))
                            HStack {
                                Text(entry.sourceName.isEmpty ? L("App sconosciuta") : entry.sourceName)
                                Spacer()
                                Text(entry.date, style: .relative)
                            }.font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Button { model.clipboard.toggleFavorite(entry.id) } label: {
                            Image(systemName: entry.favorite ? "star.fill" : "star").foregroundStyle(entry.favorite ? Color.yellow : Color.secondary)
                        }.buttonStyle(.borderless).help(L("Preferito"))
                        Button { model.clipboard.remove(entry.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).help(L("Rimuovi elemento"))
                    }.padding(.vertical, 6).tag(entry.id).onTapGesture(count: 2) { copy(entry) }
                }.listStyle(.plain).scrollContentBackground(.hidden)
                    .onKeyPress(.return) {
                        if let entry = visible.first(where: { $0.id == selection }) { copy(entry); return .handled }
                        return .ignored
                    }
            }
            Divider()
            HStack {
                Text(L("↑↓ seleziona · ⌘C copia")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("Incolla senza formattazione")) { if let entry = selectedEntry { paste(entry) } }
                    .disabled(selectedEntry == nil)
                Button(L("Copia")) { if let entry = selectedEntry { copy(entry) } }
                    .keyboardShortcut("c", modifiers: .command).disabled(selectedEntry == nil)
            }
        }.padding(18).wallpaperGlass(cornerRadius: 18).modifier(DesktopGlassGroup())
            .onAppear { searching = true }
            .onExitCommand(perform: dismiss)
            .onChange(of: visible.map(\.id), initial: true) { _, ids in
                if selection == nil || !ids.contains(selection!) { selection = ids.first }
            }
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                guard !visible.isEmpty else { return .ignored }
                let index = visible.firstIndex { $0.id == selection } ?? 0
                selection = visible[min(visible.count - 1, max(0, index + (press.key == .downArrow ? 1 : -1)))].id
                return .handled
            }
    }
}
