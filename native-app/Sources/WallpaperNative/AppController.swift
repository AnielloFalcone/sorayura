import AppKit
import SwiftUI
import CoreGraphics

@main
struct WallpaperNative {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--benchmark-agents") {
            Task.detached {
                let reader = AgentUsageReader()
                for label in ["cold", "warm", "warm-repeat"] {
                    let start = Date()
                    let result = await reader.scan()
                    print("\(label): \(String(format: "%.3f", Date().timeIntervalSince(start))) s; files=\(result.files); events=\(result.events.count); bytes=\(result.scannedBytes); parsed=\(result.parsedFiles)")
                }
                exit(0)
            }
            dispatchMain()
        }
        if CommandLine.arguments.contains("--check-agent-performance") {
            Task.detached {
                do { try await AgentPerformanceChecks.run(); exit(0) }
                catch { fputs("Agent performance check failed: \(error)\n", stderr); exit(1) }
            }
            dispatchMain()
        }
        if CommandLine.arguments.contains("--check-codex-account") {
            Task.detached {
                let result = await CodexAccountReader().read(executable: CodexAccountReader.defaultExecutable, threads: [])
                if result.quota != nil && result.error == nil {
                    print("Codex account check passed: current limits received")
                    exit(0)
                }
                fputs("Codex account check failed: \(result.error ?? "missing quota")\n", stderr)
                exit(1)
            }
            dispatchMain()
        }
        if CommandLine.arguments.contains("--claude-event") {
            try? ClaudeActivity.ingest(FileHandle.standardInput.readDataToEndOfFile())
            return
        }
        if CommandLine.arguments.contains("--claude-statusline") {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            try? ClaudeBridge.ingest(input)
            let args = CommandLine.arguments
            let index = args.firstIndex(of: "--forward-statusline")
            ClaudeBridge.forward(input, command: index.flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil })
            return
        }
        if CommandLine.arguments.contains("--check-migration") {
            if let settings = LegacyMigration.load() {
                print("Impostazioni legacy lette: \(settings.displays.count) monitor, \(settings.layers.count) livelli animazione")
                return
            }
            fputs("Impostazioni legacy non trovate\n", stderr)
            exit(1)
        }
        if CommandLine.arguments.contains("--check-localization") {
            do { try LocalizationChecks.run(); return }
            catch { fputs("Localization check failed: \(error)\n", stderr); exit(1) }
        }
        if CommandLine.arguments.contains("--check-m1") {
            do { try M1Checks.run(); return }
            catch { fputs("M1 check failed: \(error)\n", stderr); exit(1) }
        }
        if CommandLine.arguments.contains("--check-m2") {
            do { try M2Checks.run(); return }
            catch { fputs("M2 check failed: \(error)\n", stderr); exit(1) }
        }
        if CommandLine.arguments.contains("--check-observation") {
            do { try ObservationChecks.run(); return }
            catch { fputs("Observation check failed: \(error)\n", stderr); exit(1) }
        }
        if CommandLine.arguments.contains("--check-resources") {
            do { try ResourceChecks.run(); return }
            catch { fputs("Resource check failed: \(error)\n", stderr); exit(1) }
        }
        if CommandLine.arguments.contains("--check-sampling") {
            do { try SamplingChecks.run(); return }
            catch { fputs("Sampling check failed: \(error)\n", stderr); exit(1) }
        }
        if CommandLine.arguments.contains("--benchmark-sampling") {
            do { try SamplingChecks.benchmark(); return }
            catch { fputs("Sampling benchmark failed: \(error)\n", stderr); exit(1) }
        }
        if CommandLine.arguments.contains("--benchmark-geometry") {
            do { try AnimationResourceChecks.benchmark(); return }
            catch { fputs("Geometry benchmark failed: \(error)\n", stderr); exit(1) }
        }
        let application = NSApplication.shared
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.aniello.macsystemwallpaper.native")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            if CommandLine.arguments.contains("--settings") {
                DistributedNotificationCenter.default().postNotificationName(.init("dev.aniello.macsystemwallpaper.openSettings"), object: nil, userInfo: nil, deliverImmediately: true)
            }
            return
        }
        let controller = AppController()
        application.delegate = controller
        application.run()
    }
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let model = Model.shared
    private var statusItem: NSStatusItem?
    private let settingsPresentation = SettingsPresentation()
    private var componentProfile: ComponentProfile?
    private var windows: [String:NSWindow] = [:]
    private var hitWindows: [String:NSWindow] = [:]
    private var lastWallpaperSignature = ""
    private var screenSignatures: [String: String] = [:]
    private var recoveryTask: DispatchWorkItem?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do { try BrandMigration.relocate() }
        catch { fputs("Sorayura integration relocation failed: \(error)\n", stderr) }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "circle.hexagongrid", accessibilityDescription: "Sorayura")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L("Widget e sfondo…"), action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: L("Modifica layout…"), action: #selector(beginEditing), keyEquivalent: "e"))
        menu.addItem(NSMenuItem(title: L("Identifica monitor"), action: #selector(identify), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Esci"), action: #selector(quit), keyEquivalent: "q"))
        for menuItem in menu.items { menuItem.target = self }
        item.menu = menu
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .sorayuraLanguageChanged, object: nil)
        statusItem = item
        model.refreshDisplays = { [weak self] in self?.refreshScreens() }
        model.editChanged = { [weak self] editing in
            if editing { self?.componentProfile?.cancel(reason: "Editing started") }
            self?.refreshScreens()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(openSettings), name: .init("dev.aniello.macsystemwallpaper.openSettings"), object: nil)
        if let index = CommandLine.arguments.firstIndex(of: "--render-diagnostics"),
           index + 1 < CommandLine.arguments.count {
            let args = CommandLine.arguments
            let durationIndex = args.firstIndex(of: "--render-diagnostics-seconds")
            let duration = durationIndex.flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil }
            RenderDiagnostics.start(file: URL(fileURLWithPath: args[index + 1]),
                                    duration: duration?.isFinite == true ? duration! : 600)
            RenderDiagnostics.appState = { [weak self] in self?.diagnosticWindowState() ?? [:] }
        }
        refreshScreens()
        if let index = CommandLine.arguments.firstIndex(of: "--profile-components"),
           index + 1 < CommandLine.arguments.count {
            do {
                componentProfile = try ComponentProfile(model: model,
                    directory: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
            } catch { fputs("Component profile failed: \(error)\n", stderr) }
        }
        if CommandLine.arguments.contains("--settings") { openSettings() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model.save() }
    @objc private func screensChanged() {
        RenderDiagnostics.event("display_configuration_changed")
        componentProfile?.cancel(reason: "Displays changed during diagnostic")
        model.migrateDisplays()
        refreshScreens()
        scheduleRecovery()
    }
    @objc private func woke() {
        RenderDiagnostics.event("system_wake")
        componentProfile?.cancel(reason: "Wake during diagnostic")
        model.resumeSampling()
        scheduleRecovery()
    }
    @objc private func spaceChanged() {
        RenderDiagnostics.event("space_changed")
        componentProfile?.cancel(reason: "Space changed during diagnostic")
        scheduleRecovery()
    }
    private func scheduleRecovery() {
        recoveryTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lastWallpaperSignature = ""
            self.refreshScreens()
            for window in self.windows.values { window.orderFrontRegardless() }
        }
        recoveryTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: task)
    }
    @objc private func openSettings() {
        settingsPresentation.show(model: model)
    }
    @objc private func beginEditing() { model.editing = true }
    @objc private func identify() { model.identifyUntil = Date().addingTimeInterval(6) }
    @objc private func languageChanged() {
        if let menu = statusItem?.menu {
            let titles = [L("Widget e sfondo…"), L("Modifica layout…"), L("Identifica monitor"), "", L("Esci")]
            for (item, title) in zip(menu.items, titles) where !item.isSeparatorItem { item.title = title }
        }
        settingsPresentation.updateLanguage()
        refreshScreens()
    }
    @objc private func quit() { NSApp.terminate(nil) }
    private func screenID(_ screen: NSScreen) -> String { model.displayKey(screen) }
    private func diagnosticWindowState() -> [String: Any] {
        ["wallpaper_window_count": windows.count, "hit_window_count": hitWindows.count,
         "screens": orderedScreens().map { screen in
            let window = windows[screenID(screen)]
            return ["id": screenID(screen), "name": screen.localizedName,
                    "frame": NSStringFromRect(screen.frame), "scale": screen.backingScaleFactor,
                    "window_frame": window.map { NSStringFromRect($0.frame) } ?? "missing",
                    "window_visible": window?.isVisible ?? false] as [String: Any]
         }]
    }
    private func orderedScreens() -> [NSScreen] {
        guard let primary = NSScreen.screens.first else { return [] }
        return [primary] + NSScreen.screens.dropFirst().sorted {
            $0.frame.minX == $1.frame.minX ? $0.frame.minY < $1.frame.minY : $0.frame.minX < $1.frame.minX
        }
    }
    func refreshScreens() {
        let screens = orderedScreens()
        let active = Set(screens.map(screenID))
        for (id, window) in windows where !active.contains(id) { window.close(); windows[id] = nil; screenSignatures[id] = nil }
        for (id, window) in hitWindows where !active.contains(String(id.split(separator: ":").first ?? "")) { window.close(); hitWindows[id] = nil }
        let wallpaperSignature = "\(model.prefs.wallpaper)|\(model.prefs.imagePath ?? "")|\(model.prefs.syncWallpaper)|\(screens.map(screenID))"
        for screen in screens {
            let id = screenID(screen)
            let signature = "\(screen.frame)|\(screen.backingScaleFactor)|\(screen.localizedName)"
            if screenSignatures[id] != signature {
                for (key, hit) in hitWindows where key.hasPrefix("\(id):") { hit.close(); hitWindows[key] = nil }
                if let existing = windows[id] {
                    existing.contentView = NSHostingView(rootView: LocalizedRoot(content: ScreenView(screen: screen).environment(model)))
                }
                screenSignatures[id] = signature
            }
            let window: NSWindow
            if let existing = windows[id] { window = existing }
            else {
                window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.backgroundColor = .clear
                window.isOpaque = false
                window.hasShadow = false
                window.collectionBehavior = [.canJoinAllSpaces,.stationary,.ignoresCycle]
                window.contentView = NSHostingView(rootView: LocalizedRoot(content: ScreenView(screen: screen).environment(model)))
                windows[id] = window
            }
            window.setFrame(screen.frame, display: true)
            window.ignoresMouseEvents = !model.editing
            window.level = model.editing ? .normal : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            if !window.isVisible { window.orderFrontRegardless() }
            if wallpaperSignature != lastWallpaperSignature, model.prefs.syncWallpaper {
                WallpaperRenderer.apply(to: screen, prefs: model.prefs)
            }
            refreshHitWindows(for: screen)
        }
        lastWallpaperSignature = wallpaperSignature
    }
    private func refreshHitWindows(for screen: NSScreen) {
        let screenID = screenID(screen)
        let content = model.content(screen)
        let targets = content.widgets + (content.animation && model.prefs.animationStyle != "off" ? ["animation"] : [])
        let needed = Set(targets.map { "\(screenID):\($0)" })
        for (id, window) in hitWindows where id.hasPrefix("\(screenID):") && !needed.contains(id) { window.close(); hitWindows[id] = nil }
        for widget in targets {
            let id = "\(screenID):\(widget)"
            let window: NSWindow
            if let existing = hitWindows[id] { window = existing }
            else {
                let panel = NSPanel(contentRect: .zero, styleMask: [.borderless,.nonactivatingPanel], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false
                panel.hidesOnDeactivate = false
                panel.ignoresMouseEvents = false
                panel.title = "Widget · \(widget == "animation" ? L("Animazione") : Model.localizedName(widget)) · \(screenID)"
                window = panel
                window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
                window.collectionBehavior = [.canJoinAllSpaces,.stationary,.ignoresCycle]
                let hitView = LongPressView(frame: .zero)
                hitView.widgetName = widget == "animation" ? L("Animazione") : Model.localizedName(widget)
                hitView.widgetID = widget
                hitView.configuration = { [weak self] in
                    guard let self else { return WidgetDisplay() }
                    if widget == "animation" { return WidgetDisplay(chart: self.model.prefs.animationStyle) }
                    if widget.hasPrefix("agent") { return WidgetDisplay(chart: self.model.prefs.agentPeriod ?? "all", density: self.model.prefs.agentDensity ?? "compact") }
                    return widget == "memory" ? self.model.prefs.memoryDisplay : self.model.prefs.cpuDisplay
                }
                hitView.onConfigure = { [weak self] setting in
                    guard let self else { return }
                    if widget == "animation" {
                        if ["aurora", "pulse", "traces", "jarvis"].contains(setting) { self.model.prefs.animationStyle = setting }
                        return
                    }
                    if widget.hasPrefix("agent") {
                        if ["compact", "expanded"].contains(setting) { self.model.prefs.agentDensity = setting } else { self.model.prefs.agentPeriod = setting }; return
                    }
                    var value = widget == "memory" ? self.model.prefs.memoryDisplay : self.model.prefs.cpuDisplay
                    if ["compact", "expanded"].contains(setting) { value.density = setting } else { value.chart = setting }
                    if widget == "memory" { self.model.prefs.memoryDisplay = value } else { self.model.prefs.cpuDisplay = value }
                }
                hitView.setAccessibilityElement(true)
                hitView.setAccessibilityRole(.group)
                hitView.setAccessibilityLabel("Widget \(Model.localizedName(widget))")
                hitView.onEdit = { [weak self] in self?.model.editing = true }
                if widget == "animation" {
                    hitView.onBoxes = { [weak self] in
                        guard let self else { return }
                        self.settingsPresentation.navigation.section = "Animazione"
                        self.openSettings()
                    }
                }
                hitView.onRemove = { [weak self] in
                    guard let self else { return }
                    var content = self.model.content(screen)
                    if widget == "animation" { content.animation = false }
                    else { content.widgets.removeAll { $0 == widget } }
                    self.model.setContent(screen, content)
                }
                if widget == "spotify" {
                    hitView.onMusicCommand = { [weak self] command in self?.model.spotifyCommand(command) }
                    hitView.onClick = { [weak self, weak hitView] point in
                        guard let self, let hitView, point.y >= 16, point.y <= 48, point.x >= 16, point.x <= hitView.bounds.width - 16 else { return }
                        let region = Int((point.x - 16) / max(1, hitView.bounds.width - 32) * 3)
                        self.model.spotifyCommand(["previous track", "playpause", "next track"][min(2, max(0, region))])
                    }
                }
                var dragStart: Point?
                hitView.onDragStart = { [weak self] in
                    guard let self else { return }
                    dragStart = widget == "animation" ? self.model.animationPosition(screen) : self.model.position(widget, screen)
                }
                hitView.onDragEnd = { dragStart = nil }
                hitView.onDrag = { [weak self] delta in
                    guard let self else { return }
                    if widget == "animation" {
                        let start = dragStart ?? self.model.animationPosition(screen)
                        let cell = self.model.prefs.layout == "grid" ? self.model.prefs.cellSize : nil
                        let next = AnimationView.draggedPosition(start: start, delta: delta, bounds: screen.frame.size, cell: cell)
                        self.model.setAnimationPosition(screen, next)
                        return
                    }
                    let start = dragStart ?? self.model.position(widget, screen)
                    let width = self.widgetSize(widget, axis: "width", screen: screen)
                    let height = self.widgetSize(widget, axis: "height", screen: screen)
                    let currentX = screen.frame.width * start.x / 100
                    let currentY = screen.frame.height * start.y / 100
                    let x = min(max(0, currentX + delta.x), max(0, screen.frame.width - width))
                    let y = min(max(0, currentY - delta.y), max(0, screen.frame.height - height))
                    let cell = max(40, self.model.prefs.cellSize)
                    let finalX = self.model.prefs.layout == "grid" ? (x / cell).rounded() * cell : x
                    let finalY = self.model.prefs.layout == "grid" ? (y / cell).rounded() * cell : y
                    self.model.setPosition(widget, screen, Point(x: finalX / screen.frame.width * 100,
                                                                  y: finalY / screen.frame.height * 100))
                }
                window.contentView = hitView
                hitWindows[id] = window
            }
            if let hitView = window.contentView as? LongPressView {
                hitView.widgetName = widget == "animation" ? L("Animazione") : Model.localizedName(widget)
                hitView.setAccessibilityLabel(hitView.widgetName)
            }
            let rect: CGRect
            if widget == "animation" {
                rect = AnimationView.interactionRect(style: model.prefs.animationStyle, bounds: screen.frame.size,
                    scale: model.animationScale(screen), position: model.animationPosition(screen), layers: model.prefs.layers.count,
                    boxes: Dictionary(uniqueKeysWithValues: Model.animationSides.map { ($0, model.animationFields($0).count) }))
            } else {
                let point = model.position(widget, screen)
                let width = widgetSize(widget, axis: "width", screen: screen)
                let height = widgetSize(widget, axis: "height", screen: screen)
                rect = CGRect(x: min(max(0, screen.frame.width * point.x / 100), max(0, screen.frame.width - width)),
                    y: min(max(0, screen.frame.height * point.y / 100), max(0, screen.frame.height - height)), width: width, height: height)
            }
            window.setFrame(NSRect(x: screen.frame.minX + rect.minX, y: screen.frame.maxY - rect.maxY,
                                   width: rect.width, height: rect.height), display: true)
            // Widget controls take precedence where the animation overlaps them.
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + (widget == "animation" ? 1 : 2))
            if let hitView = window.contentView as? LongPressView, widget == "animation" {
                let regions = AnimationView.interactionRegions(style: model.prefs.animationStyle, bounds: screen.frame.size,
                    scale: model.animationScale(screen), position: model.animationPosition(screen), layers: model.prefs.layers.count,
                    boxes: Dictionary(uniqueKeysWithValues: Model.animationSides.map { ($0, model.animationFields($0).count) }))
                hitView.hitRegions = regions.map { CGRect(x: $0.minX - rect.minX, y: rect.maxY - $0.maxY, width: $0.width, height: $0.height) }
            }
            if model.editing { if window.isVisible { window.orderOut(nil) } } else if !window.isVisible { window.orderFrontRegardless() }
        }
    }
    private func widgetSize(_ id: String, axis: String, screen: NSScreen) -> CGFloat {
        let size = model.widgetSize(id, screen: screen)
        return axis == "width" ? size.width : size.height
    }
}

final class LongPressView: NSView {
    var widgetName = "Widget"
    var widgetID = ""
    var configuration: (() -> WidgetDisplay)?
    var onConfigure: ((String) -> Void)?
    var onEdit: (() -> Void)?
    var onBoxes: (() -> Void)?
    var hitRegions: [CGRect]? { didSet { needsDisplay = true } }
    var onRemove: (() -> Void)?
    var onClick: ((CGPoint) -> Void)?
    var onMusicCommand: ((String) -> Void)?
    var onDragStart: (() -> Void)?
    var onDragEnd: (() -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    private var timer: Timer?
    private var pressOrigin: NSPoint?
    private var dragging = false
    override func draw(_ dirtyRect: NSRect) {
        // WindowServer passes clicks through pixels with zero alpha.
        NSColor.black.withAlphaComponent(0.01).setFill()
        for region in hitRegions ?? [bounds] { region.intersection(bounds).fill() }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if let hitRegions, !hitRegions.contains(where: { $0.contains(local) }) { return nil }
        return super.hitTest(point)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        finishDrag()
        pressOrigin = NSEvent.mouseLocation
        let next = Timer(timeInterval: 0.55, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.pressOrigin != nil else { return }
                self.dragging = true
                self.onDragStart?()
                NSCursor.closedHand.push()
            }
        }
        timer = next
        RunLoop.main.add(next, forMode: .common)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let origin = pressOrigin else { return }
        let point = NSEvent.mouseLocation
        let delta = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        if dragging { onDrag?(delta) }
        else if hypot(delta.x, delta.y) > 6 { timer?.invalidate(); timer = nil }
    }
    override func mouseUp(with event: NSEvent) {
        if !dragging, let origin = pressOrigin, hypot(NSEvent.mouseLocation.x - origin.x, NSEvent.mouseLocation.y - origin.y) < 6 { onClick?(convert(event.locationInWindow, from: nil)) }
        finishDrag()
    }
    private func finishDrag() {
        timer?.invalidate()
        timer = nil
        pressOrigin = nil
        if dragging { NSCursor.pop(); onDragEnd?() }
        dragging = false
    }
    override func rightMouseDown(with event: NSEvent) {
        finishDrag()
        NSMenu.popUpContextMenu(contextMenu(), with: event, for: self)
    }
    func contextMenu() -> NSMenu {
        let menu = NSMenu(title: widgetName)
        let edit = NSMenuItem(title: L("Modifica layout…"), action: #selector(editWidget), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
        menu.addItem(.separator())
        if onMusicCommand != nil {
            for (title, command) in [("Brano precedente", "previous track"), ("Riproduci / pausa", "playpause"), ("Brano successivo", "next track")] {
                let item = NSMenuItem(title: L(title), action: #selector(musicAction(_:)), keyEquivalent: "")
                item.representedObject = command; item.target = self; menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        if widgetID == "animation" {
            let dataItem = NSMenuItem(title: L("Box dati…"), action: #selector(configureBoxes), keyEquivalent: "")
            dataItem.target = self; menu.addItem(dataItem)
            let parent = NSMenuItem(title: L("Stile"), action: nil, keyEquivalent: "")
            let sub = NSMenu(title: L("Stile"))
            let selected = configuration?().chart
            for (label, value) in [("Aurora", "aurora"), ("Impulso", "pulse"), ("Tracce · 90 secondi", "traces"), ("Nucleo luminoso", "jarvis")] {
                let item = NSMenuItem(title: L(label), action: #selector(configureAction(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = value; item.state = selected == value ? .on : .off
                sub.addItem(item)
            }
            parent.submenu = sub; menu.addItem(parent); menu.addItem(.separator())
        }
        if ["cpu", "memory"].contains(widgetID) || ["agents", "agentLive", "agentModels", "agentProjects", "agentTrend"].contains(widgetID) {
            let current = configuration?() ?? WidgetDisplay()
            let chartOptions = widgetID.hasPrefix("agent") ? [("Oggi", "today"), ("7 giorni", "week"), ("30 giorni", "month"), ("Storico", "all")] : [("Barra", "bar"), ("Linea", "line"), ("Area", "area")]
            for (title, choices, selected) in [("Dettaglio", [("Compatto", "compact"), ("Esteso", "expanded")], current.density), (widgetID.hasPrefix("agent") ? "Periodo (tutti i widget AI)" : "Grafico", chartOptions, current.chart)] {
                if widgetID == "agentTrend" && title == "Dettaglio" { continue }
                if widgetID == "agentLive" && title.hasPrefix("Periodo") { continue }
                let parent = NSMenuItem(title: L(title), action: nil, keyEquivalent: "")
                let sub = NSMenu(title: L(title))
                for (label, value) in choices {
                    let item = NSMenuItem(title: L(label), action: #selector(configureAction(_:)), keyEquivalent: "")
                    item.target = self; item.representedObject = value; item.state = selected == value ? .on : .off; sub.addItem(item)
                }
                parent.submenu = sub; menu.addItem(parent)
            }
            menu.addItem(.separator())
        }
        let remove = NSMenuItem(title: LF("Rimuovi \(widgetName)"), action: #selector(removeWidget), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)
        return menu
    }
    @objc private func configureAction(_ sender: NSMenuItem) { if let value = sender.representedObject as? String { onConfigure?(value) } }
    @objc private func musicAction(_ sender: NSMenuItem) { if let command = sender.representedObject as? String { onMusicCommand?(command) } }
    @objc private func configureBoxes() { onBoxes?() }
    @objc private func editWidget() { onEdit?() }
    @objc private func removeWidget() { onRemove?() }

}

@MainActor
enum WallpaperRenderer {
    private static var imageCache: [String:NSImage] = [:]
    static func image(for screen: NSScreen, prefs: Prefs) -> NSImage {
        if prefs.wallpaper == "image", let path = prefs.imagePath {
            let date = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
            let key = "image:\(path):\(date)"
            if let cached = imageCache[key] { return cached }
            if let image = NSImage(contentsOfFile: path) { cache(image, key: key); return image }
        }
        // Render once at display resolution (up to 4096 px), then cache. Dither
        // before 8-bit quantization rather than adding noise to an already banded image.
        let native = NSSize(width: max(1,screen.frame.width * screen.backingScaleFactor), height: max(1,screen.frame.height * screen.backingScaleFactor))
        let size = WallpaperRaster.pixelSize(native)
        let key = "dither-v1:\(prefs.wallpaper):\(Int(size.width))x\(Int(size.height))"
        if let cached = imageCache[key] { return cached }
        guard let bitmap = WallpaperRaster.bitmap(size: size, midnight: prefs.wallpaper == "midnight") else { return NSImage(size: screen.frame.size) }
        bitmap.size = screen.frame.size
        let image = NSImage(size: screen.frame.size)
        image.addRepresentation(bitmap)
        cache(image, key: key)
        return image
    }
    private static func cache(_ image: NSImage, key: String) {
        // Bound theme/resolution changes rather than retaining every old bitmap.
        let budget = 96 * 1024 * 1024
        let bytes: (NSImage) -> Int = { image in image.representations.compactMap { $0 as? NSBitmapImageRep }.reduce(0) { $0 + $1.bytesPerRow * $1.pixelsHigh } }
        if imageCache.count >= 4 || imageCache.values.reduce(0, { $0 + bytes($1) }) + bytes(image) > budget { imageCache.removeAll() }
        imageCache[key] = image
    }
    static func apply(to screen: NSScreen, prefs: Prefs) {
        autoreleasepool { applyCollected(to: screen, prefs: prefs) }
    }
    private static func applyCollected(to screen: NSScreen, prefs: Prefs) {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appending(path:"Library/Application Support/dev.aniello.macsystemwallpaper/wallpapers")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        let file = folder.appending(path:"native-\(id)-\(prefs.wallpaper).png")
        let image = image(for:screen,prefs:prefs)
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let data = NSBitmapImageRep(cgImage: cg).representation(using:.png,properties:[:]) {
            try? data.write(to:file,options:.atomic)
            do { try NSWorkspace.shared.setDesktopImageURL(file,for:screen,options:NSWorkspace.shared.desktopImageOptions(for:screen) ?? [:]) }
            catch { NSLog("Cannot set desktop image: %@",error.localizedDescription) }
        }
    }
}
