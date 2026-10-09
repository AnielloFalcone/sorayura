import AppKit
import MetalKit
import SwiftUI

struct AnimationView: View {
    let screen: NSScreen
    @Environment(Model.self) private var model

    var body: some View {
        let _ = LocalizationSettings.shared.choice
        func entry(_ id: String, color: ColorValue) -> FilamentMetric {
            let reading = model.animationReading(id)
            return FilamentMetric(id: id, color: model.metricColor(id, base: color, target: "animation").color,
                fraction: reading.fraction ?? 0, displayValue: reading.value, subtitle: reading.title,
                animated: reading.fraction != nil)
        }
        let metrics = model.prefs.layers.map { entry($0.metric, color: $0.color) }
        let boxes = Model.animationSides.compactMap { side -> FilamentBox? in
            let fields = model.animationFields(side)
            guard !fields.isEmpty else { return nil }
            return FilamentBox(side: side, entries: fields.map { id in
                entry(id, color: model.prefs.layers.first(where: { $0.metric == id })?.color ?? ColorValue("#82c4ff"))
            })
        }
        return FilamentSurface(metrics: metrics, boxes: boxes, position: model.animationPosition(screen),
                        scale: model.animationScale(screen), style: model.prefs.animationStyle,
                        frameRate: ThermalPresentation.frames(model.metrics.thermal, lowPower: model.metrics.lowPower,
                                                               adaptive: model.prefs.adaptiveAnimation ?? true),
                        paused: model.performanceVariant.pausesAnimation)
    }

    static func interactionRect(style: String, bounds: CGSize, scale: Double, position: Point, layers: Int, boxes: [String: Int]? = nil) -> CGRect {
        interactionRegions(style: style, bounds: bounds, scale: scale, position: position, layers: layers, boxes: boxes)
            .reduce(CGRect.null) { $0.union($1) }
    }
    static func interactionRegions(style: String, bounds: CGSize, scale: Double, position: Point, layers: Int, boxes: [String: Int]? = nil) -> [CGRect] {
        let size = visualSize(style: style, bounds: bounds, scale: scale)
        let center = CGPoint(x: bounds.width * position.x / 100, y: bounds.height * position.y / 100)
        var regions = [CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)]
        let contents = boxes ?? (layers > 0 ? ["right": layers] : [:])
        for (side, count) in contents where count > 0 {
            regions.append(AnimationBoxGeometry.layout(side: side, bounds: bounds, visual: size, point: position, count: count).frame)
        }
        return regions.map { $0.intersection(CGRect(origin: .zero, size: bounds)) }.filter { !$0.isEmpty }
    }
    static func draggedPosition(start: Point, delta: CGPoint, bounds: CGSize, cell: Double?) -> Point {
        func coordinate(_ start: Double, _ delta: Double, _ extent: Double) -> Double {
            let raw = start * extent / 100 + delta
            let snapped = cell.map { (raw / $0).rounded() * $0 } ?? raw
            return min(100, max(0, snapped / max(1, extent) * 100))
        }
        return Point(x: coordinate(start.x, delta.x, bounds.width), y: coordinate(start.y, -delta.y, bounds.height))
    }

    static func visualSize(style: String, bounds: CGSize, scale: Double) -> CGSize {
        let isWide = ["aurora", "pulse", "traces"].contains(style)
        let baseWidth = isWide ? min(720, bounds.width * 0.52) : min(460, min(bounds.width, bounds.height) * 0.42)
        let baseHeight = isWide ? min(650, bounds.height * 0.62) : baseWidth
        let safeScale = CGFloat(min(1.8, max(0.5, scale)))
        return CGSize(width: min(bounds.width * 0.8, baseWidth * safeScale),
                      height: min(bounds.height * 0.8, baseHeight * safeScale))
    }

}

/// Read dependencies in the SwiftUI body above; the native renderer receives
/// values and keeps its existing view and continuous frame loop.
private struct FilamentSurface: NSViewRepresentable {
    let metrics: [FilamentMetric]
    let boxes: [FilamentBox]
    let position: Point
    let scale: Double
    let style: String
    let frameRate: Int
    let paused: Bool

    func makeNSView(context: Context) -> FilamentAnimationView { FilamentAnimationView(frame: .zero) }
    func updateNSView(_ view: FilamentAnimationView, context: Context) {
        view.setFrameRate(frameRate)
        view.setRenderingPaused(paused)
        view.configure(metrics: metrics, position: position, scale: scale, style: style, boxes: boxes)
    }
    static func dismantleNSView(_ view: FilamentAnimationView, coordinator: ()) {
        view.stopRendering()
    }
}

private struct FilamentBox {
    let side: String
    let entries: [FilamentMetric]
}

private struct FilamentMetric {
    let id: String
    let color: NSColor
    let fraction: Double
    let displayValue: String
    let subtitle: String?
    let animated: Bool
    let rgb: (Float, Float, Float)

    init(id: String, color: NSColor, fraction: Double, displayValue: String, subtitle: String?, animated: Bool = true) {
        self.id = id; self.color = color; self.fraction = fraction
        self.displayValue = displayValue; self.subtitle = subtitle; self.animated = animated
        let converted = color.usingColorSpace(.deviceRGB) ?? color
        rgb = (Float(converted.redComponent), Float(converted.greenComponent), Float(converted.blueComponent))
    }
}

private struct FilamentVertex {
    var x: Float
    var y: Float
    var r: Float
    var g: Float
    var b: Float
    var a: Float
}

private final class TransparentMTKView: MTKView {
    override var isOpaque: Bool { false }
}

final class FilamentAnimationView: NSView, AnimationFrameClient {
    private let renderer = FilamentRenderer()
    private var metalView: MTKView?
    private var position = Point(x: 50, y: 50)
    private var scale = 1.0
    private var style = "jarvis"
    private var metrics: [FilamentMetric] = []
    private var boxes: [FilamentBox] = []
    private var readoutLayers: [CALayer] = []
    private var readouts: [String: CATextLayer] = [:]
    private var names: [String: CATextLayer] = [:]
    private var bars: [String: CALayer] = [:]
    private let halo = CAGradientLayer()
    private var signature = ""
    private var lastReadoutSize = CGSize.zero
    private var renderingPaused = false
    private var dataOnly = false
    private(set) var animationFrameRate = 30
    var animationFrameActive: Bool { window != nil && !renderingPaused && !dataOnly && metalView?.delegate != nil && !isHiddenOrHasHiddenAncestor }
    var animationFrameOccluded: Bool { window?.occlusionState.contains(.visible) != true }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        halo.type = .radial
        halo.startPoint = CGPoint(x: 0.5, y: 0.5)
        halo.endPoint = CGPoint(x: 1, y: 1)
        layer?.addSublayer(halo)
        if let resources = FilamentResources.shared {
            let view = TransparentMTKView(frame: .zero, device: resources.device)
            view.delegate = renderer
            view.colorPixelFormat = .bgra8Unorm
            view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            view.layer?.isOpaque = false
            view.preferredFramesPerSecond = 30
            view.enableSetNeedsDisplay = false
            view.isPaused = true
            addSubview(view)
            metalView = view
        }
        RenderDiagnostics.register(self)
        if !AnimationFrameClock.usesIndependentFrames { AnimationFrameClock.shared.register(self) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func layout() {
        super.layout()
        if lastReadoutSize != bounds.size { makeReadoutBox() }
        arrange()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateFrameScheduling()
    }

    func stopRendering() {
        metalView?.isPaused = true
        metalView?.delegate = nil
        if !AnimationFrameClock.usesIndependentFrames { AnimationFrameClock.shared.unregister(self) }
    }

    func setFrameRate(_ rate: Int) {
        animationFrameRate = rate
        if metalView?.preferredFramesPerSecond != rate { metalView?.preferredFramesPerSecond = rate }
        if !AnimationFrameClock.usesIndependentFrames { AnimationFrameClock.shared.refresh() }
    }

    func setRenderingPaused(_ paused: Bool) {
        renderingPaused = paused
        updateFrameScheduling()
    }

    private func updateFrameScheduling() {
        let paused = AnimationFrameClock.usesIndependentFrames ? window == nil || renderingPaused || dataOnly : true
        if metalView?.isPaused != paused { metalView?.isPaused = paused }
        if !AnimationFrameClock.usesIndependentFrames { AnimationFrameClock.shared.refresh() }
    }

    func drawAnimationFrame() {
        guard animationFrameActive, window?.isVisible == true else { return }
        metalView?.draw()
    }

    func renderDiagnosticState() -> [String: Any] {
        ["window_attached": window != nil, "metal_window_attached": metalView?.window != nil,
         "window_visible": window?.isVisible ?? false,
         "window_occluded": !(window?.occlusionState.contains(.visible) ?? false),
         "display": String(describing: window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]),
         "paused": AnimationFrameClock.usesIndependentFrames ? metalView?.isPaused ?? true : !animationFrameActive || AnimationFrameClock.shared.suspended,
         "automatic_mtk_paused": metalView?.isPaused ?? true,
         "frame_clock": AnimationFrameClock.usesIndependentFrames ? "independent" : "shared",
         "requested_pause": renderingPaused,
         "delegate_present": metalView?.delegate != nil, "metal_available": metalView != nil,
         "preferred_fps": metalView?.preferredFramesPerSecond ?? 0,
         "drawable_width": metalView?.drawableSize.width ?? 0,
         "drawable_height": metalView?.drawableSize.height ?? 0,
         "draw_attempts": renderer.diagnosticDrawAttempts,
         "submitted_frames": renderer.diagnosticSubmittedFrames,
         "last_submitted_uptime": renderer.diagnosticLastSubmitted]
    }

    static func checkRenderingLifecycle() throws {
        _ = NSApplication.shared
        let view = FilamentAnimationView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        guard let metal = view.metalView else { throw SettingsError.invalid("Metal unavailable in lifecycle fixture") }
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { view.stopRendering(); window.contentView = nil; window.close() }
        guard metal.isPaused else { throw SettingsError.invalid("Detached renderer is active") }
        window.contentView = view
        view.setRenderingPaused(false)
        guard view.animationFrameActive, metal.delegate != nil else { throw SettingsError.invalid("Attached renderer did not start") }
        guard metal.isPaused == !AnimationFrameClock.usesIndependentFrames else { throw SettingsError.invalid("Incorrect MTK clock mode") }
        view.setRenderingPaused(true)
        guard !view.animationFrameActive else { throw SettingsError.invalid("Diagnostic pause failed") }
        view.setRenderingPaused(false)
        guard view.animationFrameActive else { throw SettingsError.invalid("Diagnostic resume failed") }
        window.contentView = nil
        view.setRenderingPaused(false)
        guard !view.animationFrameActive else { throw SettingsError.invalid("Detached renderer did not pause") }
        window.contentView = view
        guard view.animationFrameActive else { throw SettingsError.invalid("Reattached renderer did not resume") }
    }

    fileprivate func configure(metrics: [FilamentMetric], position: Point, scale: Double, style: String, boxes: [FilamentBox]? = nil) {
        self.metrics = metrics
        self.boxes = boxes ?? (metrics.isEmpty ? [] : [FilamentBox(side: "right", entries: metrics)])
        self.position = position
        self.scale = scale
        self.style = style
        dataOnly = !metrics.contains(where: \.animated)
        metalView?.isHidden = dataOnly
        updateFrameScheduling()
        renderer.setMetrics(metrics.filter(\.animated), style: style)
        halo.isHidden = !metrics.contains(where: \.animated)
        if let color = metrics.first(where: \.animated)?.color {
            halo.colors = [color.withAlphaComponent(0.13).cgColor,
                           color.withAlphaComponent(0.035).cgColor,
                           color.withAlphaComponent(0).cgColor]
            halo.locations = [0, 0.45, 1]
        }
        arrange()
        let next = self.boxes.map { box in box.side + ":" + box.entries.map { "\($0.id):\($0.color.hexString):\($0.animated)" }.joined(separator: "|") }.joined(separator: ";") + "\(bounds.size):\(style)"
        if signature != next { signature = next; makeReadoutBox() }
        updateReadouts()
    }

    static func checkBoxFixtures() throws {
        let view = FilamentAnimationView(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let metric = FilamentMetric(id: "cpu", color: .cyan, fraction: 0.42, displayValue: "42%", subtitle: nil)
        let boxes = Model.animationSides.map { FilamentBox(side: $0, entries: [metric]) }
        view.configure(metrics: [metric], position: Point(x: 50, y: 50), scale: 1, style: "jarvis", boxes: boxes)
        guard view.readoutLayers.count == 4, view.names.count == 4, view.bars.count == 4 else { throw SettingsError.invalid("Box sides share or lose row identities") }
        guard view.readoutLayers.allSatisfy({ view.bounds.contains($0.frame) }) else { throw SettingsError.invalid("Box layout exceeds the view") }
        let text = FilamentMetric(id: "device", color: .cyan, fraction: 0, displayValue: "Mac", subtitle: nil, animated: false)
        view.configure(metrics: [], position: Point(x: 50, y: 50), scale: 1, style: "jarvis", boxes: [FilamentBox(side: "top", entries: [text])])
        guard view.readoutLayers.count == 1, view.bars.isEmpty, view.dataOnly, view.metalView?.isHidden == true else { throw SettingsError.invalid("Text information generated a progress bar or active renderer") }
        view.stopRendering()
    }

    private func arrange() {
        guard bounds.width > 1, bounds.height > 1 else { return }
        let point = CGPoint(x: bounds.width * position.x / 100, y: bounds.height * position.y / 100)
        let visualSize = AnimationView.visualSize(style: style, bounds: bounds.size, scale: scale)
        let width = visualSize.width
        let height = visualSize.height
        let visualFrame = CGRect(x: point.x - width/2, y: point.y - height/2, width: width, height: height)
        metalView?.frame = visualFrame
        halo.frame = visualFrame
        for (index, box) in boxes.enumerated() where index < readoutLayers.count {
            let geometry = AnimationBoxGeometry.layout(side: box.side, bounds: bounds.size, visual: visualSize, point: position, count: box.entries.count)
            readoutLayers[index].frame = geometry.frame
        }
    }

    private func makeReadoutBox() {
        lastReadoutSize = bounds.size
        readoutLayers.forEach { $0.removeFromSuperlayer() }
        readoutLayers.removeAll(); readouts.removeAll(); names.removeAll(); bars.removeAll()
        guard let root = layer else { return }
        let visual = AnimationView.visualSize(style: style, bounds: bounds.size, scale: scale)
        for data in boxes {
            let geometry = AnimationBoxGeometry.layout(side: data.side, bounds: bounds.size, visual: visual, point: position, count: data.entries.count)
            let box = CALayer()
            box.anchorPoint = .zero
            box.frame = geometry.frame
            box.backgroundColor = NSColor(hex: "#101a2a").withAlphaComponent(0.92).cgColor
            box.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
            box.borderWidth = 1; box.cornerRadius = 13; box.masksToBounds = true
            root.addSublayer(box); readoutLayers.append(box)
            let backingScale = window?.backingScaleFactor ?? 2
            for (index, metric) in data.entries.enumerated() {
                let key = data.side + ":" + metric.id
                let x = CGFloat(index / geometry.rows) * geometry.columnWidth
                let y = CGFloat(index % geometry.rows) * 57 + 11
                let contentWidth = max(1, geometry.columnWidth - 40)
                let marker = CALayer()
                marker.frame = CGRect(x: x + 13, y: y + 5, width: 3, height: 36)
                marker.backgroundColor = metric.color.cgColor; marker.cornerRadius = 1.5; box.addSublayer(marker)
                let name = CATextLayer()
                name.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium); name.fontSize = 10
                name.foregroundColor = NSColor.white.withAlphaComponent(0.78).cgColor
                name.frame = CGRect(x: x + 26, y: y, width: contentWidth, height: 14)
                name.contentsScale = backingScale; name.truncationMode = .end
                box.addSublayer(name); names[key] = name
                let value = CATextLayer()
                value.foregroundColor = metric.color.cgColor
                value.frame = CGRect(x: x + 26, y: y + 14, width: contentWidth, height: 27)
                value.contentsScale = backingScale; value.truncationMode = .end
                box.addSublayer(value); readouts[key] = value
                if metric.animated {
                    let track = CALayer()
                    track.frame = CGRect(x: x + 26, y: y + 43, width: contentWidth, height: 2)
                    track.backgroundColor = metric.color.withAlphaComponent(0.18).cgColor; track.cornerRadius = 1
                    box.addSublayer(track)
                    let bar = CALayer()
                    bar.bounds = CGRect(x: 0, y: 0, width: 0, height: 2); bar.anchorPoint = .zero
                    bar.position = CGPoint(x: x + 26, y: y + 43)
                    bar.backgroundColor = metric.color.cgColor; bar.cornerRadius = 1
                    box.addSublayer(bar); bars[key] = bar
                }
            }
        }
        updateReadouts()
    }

    private func updateReadouts() {
        CATransaction.begin(); CATransaction.setAnimationDuration(0.55)
        for box in boxes {
            for metric in box.entries {
                let key = box.side + ":" + metric.id
                names[key]?.string = metric.subtitle ?? Model.animationTitle(metric.id).uppercased()
                let valueSize: CGFloat = metric.displayValue.count > 17 ? 11 : metric.displayValue.count > 10 ? 14 : 19
                readouts[key]?.font = NSFont.monospacedDigitSystemFont(ofSize: valueSize, weight: .semibold)
                readouts[key]?.fontSize = valueSize
                readouts[key]?.isWrapped = metric.displayValue.count > 17
                readouts[key]?.string = metric.displayValue
                bars[key]?.bounds.size.width = max(0, (readouts[key]?.bounds.width ?? 180)) * CGFloat(metric.fraction)
            }
        }
        CATransaction.commit()
    }

}

private final class FilamentRenderer: NSObject, MTKViewDelegate {
    var diagnosticDrawAttempts = 0
    var diagnosticSubmittedFrames = 0
    var diagnosticLastSubmitted = 0.0
    private struct StrandSample {
        let latitudeCos: Float
        let latitudeSin: Float
        let azimuthBase: Float
        let radiusBase: Float
        let taper: Float
    }
    private var strandSamples: [[StrandSample]] = []
    private var templateMetricCount = -1
    private let resources = FilamentResources.shared
    private let framePool = FilamentResources.shared.map { MetalFramePool(device: $0.device) }
    private var fill: [FilamentVertex] = []
    private var glow: [FilamentVertex] = []
    private var fine: [FilamentVertex] = []
    private var points: [(Float, Float, Float)] = []
    private var metrics: [FilamentMetric] = []
    private var style = "jarvis"
    private var smoothed: [String: Double] = [:]
    private var history: [String: [Float]] = [:]
    private var lastHistorySample = -1.0
    private let start = CACurrentMediaTime()
    private let queue = DispatchQueue(label: "wallpaper.filaments.metrics")

    fileprivate func setMetrics(_ values: [FilamentMetric], style: String) {
        queue.sync { metrics = values; self.style = style }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        autoreleasepool { drawFrame(in: view) }
    }

    @MainActor private func drawFrame(in view: MTKView) {
        if RenderDiagnostics.enabled { diagnosticDrawAttempts += 1 }
        // Never wait for the GPU on the UI thread, or acquire a drawable when
        // all slots are busy. Missing/failed drawables return the lease too.
        guard let resources, let framePool, let slot = framePool.acquire() else { return }
        var transferred = false
        defer { if !transferred { framePool.release(slot) } }
        guard let batch = AnimationFrameClock.currentBatch ?? MetalFrameBatch() else { return }
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let encoder = batch.command.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        let (current, style) = queue.sync { (metrics, self.style) }
        buildGeometry(metrics: current, style: style, time: CACurrentMediaTime() - start,
                      width: max(1, view.drawableSize.width), height: max(1, view.drawableSize.height))
        let vertexCount = fill.count + glow.count + fine.count
        encoder.setRenderPipelineState(resources.pipeline)
        if vertexCount > 0 {
            guard let buffer = framePool.buffer(for: slot, length: vertexCount * MemoryLayout<FilamentVertex>.stride) else {
                encoder.endEncoding()
                return
            }
            var byteOffset = 0
            func upload(_ vertices: [FilamentVertex]) {
                vertices.withUnsafeBytes { bytes in
                    if let source = bytes.baseAddress, !bytes.isEmpty {
                        buffer.contents().advanced(by: byteOffset).copyMemory(from: source, byteCount: bytes.count)
                        byteOffset += bytes.count
                    }
                }
            }
            upload(fill); upload(glow); upload(fine)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            // All ranges use the same pipeline and contiguous triangle data.
            // Preserve their order while submitting one draw instead of three.
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        }
        encoder.endEncoding()
        batch.command.present(drawable)
        batch.add(pool: framePool, slot: slot) { [weak self] in
            if RenderDiagnostics.enabled {
                self?.diagnosticSubmittedFrames += 1
                self?.diagnosticLastSubmitted = ProcessInfo.processInfo.systemUptime
            }
        }
        transferred = true
        if AnimationFrameClock.currentBatch == nil { batch.commit() }
    }

    private func buildGeometry(metrics current: [FilamentMetric], style: String, time: Double,
                               width: CGFloat, height: CGFloat) {
        if time - lastHistorySample >= 1 {
            lastHistorySample = time
            for metric in current {
                var samples = history[metric.id] ?? []
                samples.append(Float(metric.fraction))
                if samples.count > 90 { samples.removeFirst(samples.count - 90) }
                history[metric.id] = samples
            }
        }
        fill.removeAll(keepingCapacity: true)
        glow.removeAll(keepingCapacity: true)
        fine.removeAll(keepingCapacity: true)
        if style == "aurora" {
            makeAurora(metrics: current, time: time, canvasWidth: width, canvasHeight: height,
                       fill: &fill, glow: &glow, fine: &fine)
        } else if style == "pulse" {
            makePulse(metrics: current, time: time, canvasWidth: width, canvasHeight: height,
                      glow: &glow, fine: &fine)
        } else if style == "traces" {
            makeTraces(metrics: current, canvasWidth: width, canvasHeight: height,
                       glow: &glow, fine: &fine)
        } else {
        let strands = current.count > 3 ? 1 : 2
        if templateMetricCount != current.count {
            templateMetricCount = current.count
            strandSamples = current.indices.flatMap { index in
                (0..<strands).map { strand in
                    let phase = Float(index) * 1.47 + Float(strand) * 2.3
                    return (0...160).map { step in
                        let u = Float(step) / 160
                        let latitude = sin(u * 1.65 * .pi + phase * 0.7) * 0.78
                        return StrandSample(latitudeCos: cos(latitude), latitudeSin: sin(latitude),
                                            azimuthBase: u * 2.55 * .pi + phase,
                                            radiusBase: u * 5 * .pi,
                                            taper: pow(max(0, sin(u * .pi)), 0.8))
                    }
                }
            }
        }
        for (index, metric) in current.enumerated() {
            let previous = smoothed[metric.id] ?? metric.fraction
            let level = previous + (metric.fraction - previous) * 0.045
            smoothed[metric.id] = level
            let activity = Float(0.38 + level * 0.62)
            let rgb = (metric.rgb.0 * 0.82 + 0.18,
                       metric.rgb.1 * 0.82 + 0.18,
                       metric.rgb.2 * 0.82 + 0.18)
            let spin = Float(time) * 0.12 + Float(index) * 0.5
            let spinCos = cos(spin), spinSin = sin(spin)
            for strand in 0..<strands {
                points.removeAll(keepingCapacity: true)
                let samples = strandSamples[index * strands + strand]
                let phase = Float(index) * 1.47 + Float(strand) * 2.3
                let tilt: Float = 0.32 + Float(strand) * 0.28
                let tiltCos = cos(tilt), tiltSin = sin(tilt)
                let motion = Float(time) * (strand == 0 ? 0.22 : -0.18)
                for step in 0...160 {
                    let sample = samples[step]
                    let azimuth = sample.azimuthBase + motion
                    let radius: Float = 0.62 + 0.055 * sin(sample.radiusBase + Float(time) * 0.7 + phase)
                    var x = sample.latitudeCos * cos(azimuth) * radius
                    var y = sample.latitudeSin * radius
                    var z = sample.latitudeCos * sin(azimuth) * radius
                    let rotatedX = x * spinCos - z * spinSin
                    z = x * spinSin + z * spinCos
                    x = rotatedX
                    let rotatedY = y * tiltCos - z * tiltSin
                    z = y * tiltSin + z * tiltCos
                    y = rotatedY
                    let perspective = 1 / (1.6 - z * 0.55)
                    points.append((x * perspective, y * perspective, z))
                }
                for step in 0..<160 {
                    let p = points[step], q = points[step + 1]
                    let depth = max(0.25, min(1, (p.2 + 0.45) * 1.35))
                    let taper = samples[step].taper
                    appendSegment(&glow, p, q, rgb, width: 22, alpha: 0.16 * depth * activity * taper, canvasWidth: width, canvasHeight: height)
                    appendSegment(&fine, p, q, rgb, width: 2.5, alpha: 0.92 * depth * activity * taper, canvasWidth: width, canvasHeight: height)
                }
            }
        }
        }
    }

    private func makeAurora(metrics: [FilamentMetric], time: Double,
                            canvasWidth: CGFloat, canvasHeight: CGFloat,
                            fill: inout [FilamentVertex], glow: inout [FilamentVertex],
                            fine: inout [FilamentVertex]) {
        let visible = metrics
        guard !visible.isEmpty else { return }
        let count = Float(visible.count)
        let spacing = min(0.78, 1.72 / count)
        for (index, metric) in visible.enumerated() {
            let previous = smoothed[metric.id] ?? metric.fraction
            let level = previous + (metric.fraction - previous) * 0.045
            smoothed[metric.id] = level
            let amount = Float(level)
            let base = (Float(index) - (count - 1) / 2) * spacing
            let amplitude = spacing * (0.14 + amount * 0.75)
            let phase = Float(index) * 1.21
            let rgb = (metric.rgb.0 * 0.85 + 0.15,
                       metric.rgb.1 * 0.85 + 0.15,
                       metric.rgb.2 * 0.85 + 0.15)
            func crest(_ x: Float) -> Float {
                let motion = x * 4.6 - Float(time) * 0.55 + phase
                let contour = 0.78 + 0.12 * sin(motion) + 0.06 * sin(x * 10.8 + Float(time) * 0.31 + phase)
                return base + amplitude * contour
            }
            for step in 0..<128 {
                let x0 = -0.89 + Float(step) / 128 * 1.78
                let x1 = -0.89 + Float(step + 1) / 128 * 1.78
                let top0 = crest(x0), top1 = crest(x1)
                let bottom = base - spacing * 0.20
                let fillAlpha: Float = 0.13 + amount * 0.11
                appendCurtain(&fill, x0: x0, x1: x1, bottom: bottom,
                              top0: top0, top1: top1, color: rgb, alpha: fillAlpha)
                let p = (x0, top0, Float(0)), q = (x1, top1, Float(0))
                appendSegment(&glow, p, q, rgb, width: 34,
                              alpha: 0.07 + amount * 0.06,
                              canvasWidth: canvasWidth, canvasHeight: canvasHeight)
                appendSegment(&fine, p, q, rgb, width: 1.2,
                              alpha: 0.24 + amount * 0.12,
                              canvasWidth: canvasWidth, canvasHeight: canvasHeight)
                if step.isMultiple(of: 5) {
                    let rayHeight = top0 - bottom
                    let rayStart = bottom + rayHeight * 0.08
                    appendSegment(&fine, (x0, rayStart, 0), (x0, top0, 0), rgb,
                                  width: 1.4, alpha: 0.10 + amount * 0.10,
                                  canvasWidth: canvasWidth, canvasHeight: canvasHeight)
                }
            }
        }
    }

    private func makePulse(metrics: [FilamentMetric], time: Double,
                           canvasWidth: CGFloat, canvasHeight: CGFloat,
                           glow: inout [FilamentVertex], fine: inout [FilamentVertex]) {
        guard !metrics.isEmpty else { return }
        let lane = min(0.75, 1.7 / Float(metrics.count))
        for (index, metric) in metrics.enumerated() {
            let previous = smoothed[metric.id] ?? metric.fraction
            let level = previous + (metric.fraction - previous) * 0.045
            smoothed[metric.id] = level
            let amount = Float(level)
            let baseline = (Float(index) - Float(metrics.count - 1) / 2) * lane
            let rgb = metric.rgb
            let period = 2.8 - amount * 1.65
            let travel = Float(time) / period + Float(index) * 0.17
            let peak = -0.88 + (travel - floor(travel)) * 1.76
            let amplitude = lane * (0.09 + amount * 0.57)
            func wave(_ x: Float) -> Float {
                let distance = (x - peak) / (0.075 + amount * 0.025)
                let spike = exp(-distance * distance * 3.2)
                let recovery = exp(-pow((distance - 1.5) * 1.3, 2)) * 0.30
                return baseline + amplitude * (spike - recovery)
            }
            appendSegment(&fine, (-0.89, baseline, 0), (0.89, baseline, 0), rgb,
                          width: 1, alpha: 0.15, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
            for step in 0..<160 {
                let x0 = -0.89 + Float(step) / 160 * 1.78
                let x1 = -0.89 + Float(step + 1) / 160 * 1.78
                let p = (x0, wave(x0), Float(0)), q = (x1, wave(x1), Float(0))
                let light = 0.24 + 0.68 * exp(-pow((x0 - peak) * 5, 2))
                appendSegment(&glow, p, q, rgb, width: 18,
                              alpha: 0.09 * light, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
                appendSegment(&fine, p, q, rgb, width: 2.1,
                              alpha: light, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
            }
        }
    }

    private func makeTraces(metrics: [FilamentMetric], canvasWidth: CGFloat,
                            canvasHeight: CGFloat, glow: inout [FilamentVertex],
                            fine: inout [FilamentVertex]) {
        guard !metrics.isEmpty else { return }
        let lane = min(0.75, 1.7 / Float(metrics.count))
        for (index, metric) in metrics.enumerated() {
            let center = (Float(index) - Float(metrics.count - 1) / 2) * lane
            let bottom = center - lane * 0.31
            let rgb = metric.rgb
            let samples = history[metric.id] ?? []
            guard samples.count > 1 else { continue }
            for sample in 1..<samples.count {
                let x0 = 0.89 - Float(samples.count - sample) / 89 * 1.78
                let x1 = 0.89 - Float(samples.count - sample - 1) / 89 * 1.78
                let y0 = bottom + min(1, max(0, samples[sample - 1])) * lane * 0.65
                let y1 = bottom + min(1, max(0, samples[sample])) * lane * 0.65
                let p = (x0, y0, Float(0)), q = (x1, y1, Float(0))
                appendSegment(&glow, p, q, rgb, width: 15, alpha: 0.09,
                              canvasWidth: canvasWidth, canvasHeight: canvasHeight)
                appendSegment(&fine, p, q, rgb, width: 2.2, alpha: 0.82,
                              canvasWidth: canvasWidth, canvasHeight: canvasHeight)
            }
        }
    }

    private func appendCurtain(_ vertices: inout [FilamentVertex], x0: Float, x1: Float,
                               bottom: Float, top0: Float, top1: Float,
                               color: (Float, Float, Float), alpha: Float) {
        let a = FilamentVertex(x:x0,y:bottom,r:color.0,g:color.1,b:color.2,a:0.003)
        let b = FilamentVertex(x:x1,y:bottom,r:color.0,g:color.1,b:color.2,a:0.003)
        let c = FilamentVertex(x:x0,y:top0,r:color.0,g:color.1,b:color.2,a:alpha)
        let d = FilamentVertex(x:x1,y:top1,r:color.0,g:color.1,b:color.2,a:alpha)
        vertices.append(a); vertices.append(b); vertices.append(c)
        vertices.append(b); vertices.append(d); vertices.append(c)
    }

    private func appendSegment(_ vertices: inout [FilamentVertex], _ p: (Float,Float,Float), _ q: (Float,Float,Float),
                               _ color: (Float,Float,Float), width: Float, alpha: Float,
                               canvasWidth: CGFloat, canvasHeight: CGFloat) {
        let dx = q.0 - p.0, dy = q.1 - p.1
        let length = max(0.0001, sqrt(dx * dx + dy * dy))
        let normalX = -dy / length * width / Float(canvasWidth)
        let normalY = dx / length * width / Float(canvasHeight)
        let a = FilamentVertex(x:p.0 + normalX, y:p.1 + normalY, r:color.0,g:color.1,b:color.2,a:alpha)
        let b = FilamentVertex(x:p.0 - normalX, y:p.1 - normalY, r:color.0,g:color.1,b:color.2,a:alpha)
        let c = FilamentVertex(x:q.0 + normalX, y:q.1 + normalY, r:color.0,g:color.1,b:color.2,a:alpha)
        let d = FilamentVertex(x:q.0 - normalX, y:q.1 - normalY, r:color.0,g:color.1,b:color.2,a:alpha)
        vertices.append(a); vertices.append(b); vertices.append(c)
        vertices.append(b); vertices.append(d); vertices.append(c)
    }

    static func checkGeometry() throws {
        func check(_ passed: Bool, _ message: String) throws {
            if !passed { throw SettingsError.invalid(message) }
        }
        try check(MemoryLayout<FilamentVertex>.stride == 6 * MemoryLayout<Float>.stride,
                  "Vertex layout no longer matches the Metal shader")
        let renderer = FilamentRenderer()
        let metrics = ["cpu", "memory", "network", "battery", "disk"].enumerated().map {
            FilamentMetric(id: $0.element, color: .cyan, fraction: Double($0.offset + 1) / 6,
                           displayValue: "Fixture", subtitle: nil)
        }
        let expected = [("jarvis", 0, 4800, 4800), ("aurora", 3840, 3840, 4620),
                        ("pulse", 0, 4800, 4830), ("traces", 0, 90, 90)]
        for (index, fixture) in expected.enumerated() {
            renderer.buildGeometry(metrics: metrics, style: fixture.0, time: Double(index * 2), width: 920, height: 920)
            try check(renderer.fill.count == fixture.1 && renderer.glow.count == fixture.2 && renderer.fine.count == fixture.3,
                      "Stale or missing vertices after switching to \(fixture.0)")
            for vertices in [renderer.fill, renderer.glow, renderer.fine] {
                try check(vertices.allSatisfy { [$0.x, $0.y, $0.r, $0.g, $0.b, $0.a].allSatisfy(\.isFinite) },
                          "Invalid vertex in \(fixture.0)")
            }
        }
        renderer.buildGeometry(metrics: [], style: "jarvis", time: 8, width: 920, height: 920)
        try check(renderer.fill.isEmpty && renderer.glow.isEmpty && renderer.fine.isEmpty,
                  "Removed animation layers remain in reused arrays")
        renderer.buildGeometry(metrics: Array(metrics.prefix(3)), style: "jarvis", time: 10, width: 920, height: 920)
        try check(renderer.glow.count == 5760 && renderer.fine.count == 5760,
                  "Two-strand geometry changed")
        let fixture = FilamentRenderer()
        let referenceMetrics = ["cpu", "memory", "network"].enumerated().map {
            FilamentMetric(id: $0.element, color: .cyan, fraction: [0.25, 0.60, 0.08][$0.offset],
                           displayValue: "Fixture", subtitle: nil)
        }
        fixture.buildGeometry(metrics: referenceMetrics, style: "jarvis", time: 24, width: 920, height: 920)
        // Frozen vertices from the preceding release, rather than a second
        // implementation of the curve equations in the test.
        let golden: [[Float]] = [[-0.36111593, 0.14873406, 0.20747206],
                                 [0.30244878, 0.17630574, 0.21391253],
                                 [-0.23029917, -0.29000109, 0.16209663]]
        for (index, expected) in zip([120, 480, 840], golden) {
            let vertex = fixture.fine[index]
            try check(zip([vertex.x, vertex.y, vertex.a], expected).allSatisfy { abs($0 - $1) < 0.000001 },
                      "Cached Jarvis geometry differs from its release reference")
        }
    }

    static func benchmarkGeometry() -> [[String: Any]] {
        let metrics = ["cpu", "memory", "network"].enumerated().map {
            FilamentMetric(id: $0.element, color: .cyan, fraction: [0.25, 0.60, 0.08][$0.offset],
                           displayValue: "Fixture", subtitle: nil)
        }
        var results: [[String: Any]] = []
        for style in ["jarvis", "aurora", "pulse", "traces"] {
            let renderer = FilamentRenderer()
            for tick in 0..<90 { renderer.buildGeometry(metrics: metrics, style: style, time: Double(tick), width: 920, height: 920) }
            let began = ProcessInfo.processInfo.systemUptime
            var checksum: Float = 0
            for frame in 0..<120 {
                renderer.buildGeometry(metrics: metrics, style: style, time: 90 + Double(frame)/30, width: 920, height: 920)
                checksum += renderer.fine.first?.x ?? 0
            }
            let ms = (ProcessInfo.processInfo.systemUptime - began) * 1000
            renderer.buildGeometry(metrics: metrics, style: style, time: 24, width: 920, height: 920)
            let reference: [[Float]] = [120, 480, 840].filter { $0 < renderer.fine.count }.map {
                let v = renderer.fine[$0]; return [v.x, v.y, v.a]
            }
            results.append(["style":style,"frames":120,"cpu_geometry_wall_mean_ms":ms/120,
                            "checksum":checksum,"reference_vertices":reference])
        }
        return results
    }

    static func checkCombinedRendering() throws {
        guard let resources = FilamentResources.shared else { throw SettingsError.invalid("Metal unavailable") }
        let renderer = FilamentRenderer()
        let metrics = ["cpu", "memory", "network"].enumerated().map {
            FilamentMetric(id: $0.element, color: [NSColor.red, .green, .blue][$0.offset],
                           fraction: [0.25, 0.60, 0.08][$0.offset], displayValue: "Fixture", subtitle: nil)
        }
        for style in ["jarvis", "aurora", "pulse", "traces"] {
            for tick in 0..<90 {
                renderer.buildGeometry(metrics: metrics, style: style, time: Double(tick), width: 128, height: 128)
            }
            let vertices = renderer.fill + renderer.glow + renderer.fine
            let counts = [renderer.fill.count, renderer.glow.count, renderer.fine.count]
            guard !vertices.isEmpty,
                  let buffer = vertices.withUnsafeBytes({ bytes in
                      resources.device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
                  }) else { throw SettingsError.invalid("No vertices for render fixture") }
            func render(combined: Bool) throws -> [UInt8] {
                let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm, width: 128, height: 128, mipmapped: false)
                textureDescriptor.storageMode = .shared
                textureDescriptor.usage = .renderTarget
                guard let texture = resources.device.makeTexture(descriptor: textureDescriptor),
                      let command = resources.commandQueue.makeCommandBuffer() else {
                    throw SettingsError.invalid("Cannot create render fixture")
                }
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = texture
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].storeAction = .store
                pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
                guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
                    throw SettingsError.invalid("Cannot encode render fixture")
                }
                encoder.setRenderPipelineState(resources.pipeline)
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                if combined { encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count) }
                else {
                    var start = 0
                    for count in counts {
                        if count > 0 { encoder.drawPrimitives(type: .triangle, vertexStart: start, vertexCount: count) }
                        start += count
                    }
                }
                encoder.endEncoding()
                let completed = DispatchGroup(); completed.enter()
                command.addCompletedHandler { _ in completed.leave() }
                command.commit()
                guard completed.wait(timeout: .now() + 5) == .success,
                      command.status == .completed, command.error == nil else {
                    throw SettingsError.invalid("Render fixture failed to complete")
                }
                var bytes = [UInt8](repeating: 0, count: 128 * 128 * 4)
                bytes.withUnsafeMutableBytes { data in
                    texture.getBytes(data.baseAddress!, bytesPerRow: 128 * 4,
                                     from: MTLRegionMake2D(0, 0, 128, 128), mipmapLevel: 0)
                }
                return bytes
            }
            let separate = try render(combined: false), combined = try render(combined: true)
            guard separate.contains(where: { $0 != 0 }), separate == combined else {
                throw SettingsError.invalid("Combined draw changed \(style) pixels")
            }
        }
    }
}

enum AnimationResourceChecks {
    @MainActor static func run() throws {
        try FilamentAnimationView.checkRenderingLifecycle()
        try FilamentRenderer.checkGeometry()
        try FilamentRenderer.checkCombinedRendering()
    }
    static func benchmark() throws {
        let result: [String: Any] = ["scope":"Small serial CPU geometry fixture, 3 layers at 920x920; excludes GPU, drawable acquisition, compositor and SwiftUI", "results":FilamentRenderer.benchmarkGeometry()]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}

private extension NSColor {
    var hexString: String {
        let color = usingColorSpace(.deviceRGB) ?? self
        return String(format: "%02x%02x%02x", Int(color.redComponent * 255), Int(color.greenComponent * 255), Int(color.blueComponent * 255))
    }
}
