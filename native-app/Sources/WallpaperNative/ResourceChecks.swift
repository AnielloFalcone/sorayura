import AppKit
import Metal

/// Small fixtures only: no wallpaper windows, user settings writes or stress load.
@MainActor enum ResourceChecks {
    static func run() throws {
        try settingsLifetime()
        try wallpaperRaster()
        try animationInteractions()
        try buffers()
        try AnimationResourceChecks.run()
        try FilamentAnimationView.checkBoxFixtures()
        try ComponentProfile.checkFixtures()
        try AnimationFrameClock.checkFixtures()
        try batchedPasses()
        print("Resource checks passed: settings lifetime, bounded GPU buffers, reference pixels, frame clock, multi-display batch leases and diagnostic restoration")
    }

    private static func check(_ passed: Bool, _ message: String) throws {
        if !passed { throw SettingsError.invalid(message) }
    }

    private static func wallpaperRaster() throws {
        try check(WallpaperRaster.pixelSize(CGSize(width: 3840, height: 2160)) == CGSize(width: 3840, height: 2160), "4K wallpaper is downscaled")
        try check(WallpaperRaster.pixelSize(CGSize(width: 5120, height: 2880)) == CGSize(width: 4096, height: 2304), "Wallpaper resolution cap changed")
        for midnight in [false, true] {
            guard let first = WallpaperRaster.bitmap(size: CGSize(width: 512, height: 320), midnight: midnight),
                  let second = WallpaperRaster.bitmap(size: CGSize(width: 512, height: 320), midnight: midnight),
                  let a = first.bitmapData, let b = second.bitmapData,
                  let png = first.representation(using: .png, properties: [:]),
                  let decoded = NSBitmapImageRep(data: png) else { throw SettingsError.invalid("Wallpaper raster/PNG unavailable") }
            try check(!first.hasAlpha && first.samplesPerPixel == 3, "Wallpaper retains an unnecessary alpha channel")
            for y in 0..<320 {
                try check(memcmp(a + y * first.bytesPerRow, b + y * second.bytesPerRow, 512 * 3) == 0, "Wallpaper dithering changes across renders")
            }
            var reversals = 0
            for x in 1..<511 {
                let offset = 160 * first.bytesPerRow + x * 3
                let before = Int(a[offset]) - Int(a[offset - 3])
                let after = Int(a[offset + 3]) - Int(a[offset])
                if before * after < 0 { reversals += 1 }
            }
            try check(reversals > 10, "Gradient quantization lacks spatial dithering")
            for x in stride(from: 0, to: 512, by: 31) {
                guard let original = first.colorAt(x: x, y: 160)?.usingColorSpace(.sRGB),
                      let restored = decoded.colorAt(x: x, y: 160)?.usingColorSpace(.sRGB) else { throw SettingsError.invalid("Wallpaper pixel unreadable") }
                try check(abs(original.redComponent - restored.redComponent) < 0.001 && abs(original.blueComponent - restored.blueComponent) < 0.001, "PNG changed wallpaper colors")
            }
        }
    }

    private static func animationInteractions() throws {
        let bounds = CGSize(width: 1440, height: 900)
        for style in ["aurora", "pulse", "traces", "ribbon", "jarvis"] {
            let rect = AnimationView.interactionRect(style: style, bounds: bounds, scale: 1.8, position: Point(x: 95, y: 5), layers: 5)
            try check(!rect.isEmpty && CGRect(origin: .zero, size: bounds).contains(rect), "Animation interaction area exceeds its display")
            let middle = AnimationView.interactionRect(style: style, bounds: bounds, scale: 1, position: Point(x: 50, y: 50), layers: 3)
            try check(middle.contains(CGPoint(x: 720, y: 450)) && middle.maxX > 900, "Animation hit area omits the visual or readouts")
        }
        let dragged = AnimationView.draggedPosition(start: Point(x: 50, y: 50), delta: CGPoint(x: 144, y: -90), bounds: bounds, cell: nil)
        try check(dragged.x == 60 && dragged.y == 60, "Animation drag uses the wrong center or vertical direction")
        let bounded = AnimationView.draggedPosition(start: Point(x: 99, y: 1), delta: CGPoint(x: 1000, y: 1000), bounds: bounds, cell: 130)
        try check(bounded.x == 100 && bounded.y == 0, "Animation grid drag escapes the display")
        let view = LongPressView(frame: .zero)
        view.widgetID = "animation"; view.widgetName = L("Animazione")
        view.configuration = { WidgetDisplay(chart: "jarvis") }
        var edited = false, removed = false, selected = ""
        view.onEdit = { edited = true }; view.onRemove = { removed = true }; view.onConfigure = { selected = $0 }
        let menu = view.contextMenu()
        try check(menu.items.first?.title == L("Modifica layout…") && menu.items.last?.title == LF("Rimuovi \(L("Animazione"))"), "Animation menu lacks shared edit/remove actions")
        let styles = menu.items.compactMap(\.submenu).first!
        try check(styles.items.count == 5 && styles.items.last?.state == .on, "Animation styles missing or selection incorrect")
        menu.performActionForItem(at: 0)
        styles.performActionForItem(at: 1)
        menu.performActionForItem(at: menu.items.count - 1)
        try check(edited && removed && selected == "pulse", "Animation menu callbacks are disconnected")
    }

    private static func settingsLifetime() throws {
        _ = NSApplication.shared
        let presentation = SettingsPresentation()
        let model = Model.isolated()
        weak var hosting: NSView?
        var frame = NSRect.zero
        try autoreleasepool {
            let first = presentation.prepare(model: model)
            try check(presentation.prepare(model: model) === first, "Duplicate settings windows on repeated open")
            hosting = first.contentView
            try check(hosting != nil, "Settings content missing")
            presentation.navigation.section = "Widget"
            frame = first.frame.offsetBy(dx: 20, dy: 20)
            first.setFrame(frame, display: false)
            first.close()
            try check(presentation.window == nil && first.contentView == nil,
                      "Closing settings still retains the hosting tree")
        }
        try check(hosting == nil, "Settings hosting view did not deallocate after close")
        try autoreleasepool {
            let second = presentation.prepare(model: model)
            try check(second.contentView != nil && presentation.navigation.section == "Widget",
                      "Reopened settings lost navigation or content")
            try check(second.frame == frame, "Reopened settings lost their window frame")
            second.close()
        }
        try check(presentation.window == nil, "Reopened settings remain retained after close")
    }

    private static func buffers() throws {
        guard let resources = FilamentResources.shared else { throw SettingsError.invalid("Metal unavailable") }
        let pool = MetalFramePool(device: resources.device)
        var held: [Int] = []
        for _ in 0..<3 {
            guard let slot = pool.acquire() else { throw SettingsError.invalid("Missing frame slot") }
            held.append(slot)
        }
        try check(Set(held).count == 3 && pool.acquire() == nil, "More than three frames can be in flight")
        // Return a middle slot first: a still-busy slot must never be selected.
        pool.release(held[1])
        let reclaimed = pool.acquire()
        try check(reclaimed == held[1] && pool.acquire() == nil, "Out-of-order completion reused a busy slot")

        var originals: [Int: MTLBuffer] = [:]
        var copies: [(Int, MTLBuffer, MTLCommandBuffer)] = []
        let completed = DispatchGroup()
        for slot in held {
            guard let input = pool.buffer(for: slot, length: 256),
                  let output = resources.device.makeBuffer(length: 256, options: .storageModeShared),
                  let command = resources.commandQueue.makeCommandBuffer(),
                  let encoder = command.makeBlitCommandEncoder() else { throw SettingsError.invalid("Cannot create GPU fixture") }
            try check(pool.buffer(for: slot, length: 128) === input, "Stable-size frame allocates a new buffer")
            originals[slot] = input
            input.contents().initializeMemory(as: UInt8.self, repeating: UInt8(slot + 17), count: 256)
            encoder.copy(from: input, sourceOffset: 0, to: output, destinationOffset: 0, size: 256)
            encoder.endEncoding()
            completed.enter()
            command.addCompletedHandler { [pool] _ in pool.release(slot); completed.leave() }
            copies.append((slot, output, command))
            command.commit()
        }
        try check(completed.wait(timeout: .now() + 5) == .success, "GPU fixture did not complete")
        for (slot, output, command) in copies {
            try check(command.status == .completed && command.error == nil, "GPU command failed")
            let bytes = UnsafeBufferPointer(start: output.contents().assumingMemoryBound(to: UInt8.self), count: 256)
            try check(bytes.allSatisfy { $0 == UInt8(slot + 17) }, "GPU read corrupted reused data")
        }
        var reacquired: [Int] = []
        for _ in 0..<3 {
            guard let slot = pool.acquire() else { throw SettingsError.invalid("GPU completion lost a slot") }
            reacquired.append(slot)
            try check(pool.buffer(for: slot, length: 256) === originals[slot], "Completed frame discarded reusable buffer")
        }
        try check(Set(reacquired) == Set(held) && pool.acquire() == nil, "Completion changed the frame limit")
        let growing = reacquired[0]
        let large = pool.buffer(for: growing, length: 100_000)
        try check(large != nil && large!.length >= 100_000 && large !== originals[growing], "Frame growth failed")
        try check(pool.buffer(for: growing, length: 200) === large, "Buffer shrinks/reallocates on a smaller frame")
        for slot in reacquired.dropFirst() {
            try check(pool.buffer(for: slot, length: 256) === originals[slot], "Growing one slot replaced another slot")
        }
        reacquired.forEach { pool.release($0) }
    }

    private static func batchedPasses() throws {
        guard let resources = FilamentResources.shared, let batch = MetalFrameBatch() else {
            throw SettingsError.invalid("Metal batch unavailable")
        }
        var textures: [MTLTexture] = []
        var leased: [(MetalFramePool, Int)] = []
        let colors = [MTLClearColor(red: 1, green: 0, blue: 0, alpha: 1),
                      MTLClearColor(red: 0, green: 1, blue: 0, alpha: 1),
                      MTLClearColor(red: 0, green: 0, blue: 1, alpha: 1)]
        var callbacks = 0
        for color in colors {
            let pool = MetalFramePool(device: resources.device)
            guard let slot = pool.acquire() else { throw SettingsError.invalid("No batch slot") }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 8, height: 8, mipmapped: false)
            descriptor.storageMode = .shared; descriptor.usage = .renderTarget
            guard let texture = resources.device.makeTexture(descriptor: descriptor) else { throw SettingsError.invalid("No batch texture") }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = color
            guard let encoder = batch.command.makeRenderCommandEncoder(descriptor: pass) else { throw SettingsError.invalid("No batch encoder") }
            encoder.endEncoding()
            batch.add(pool: pool, slot: slot) { callbacks += 1 }
            let other = [pool.acquire(), pool.acquire()].compactMap { $0 }
            try check(other.count == 2 && !other.contains(slot) && pool.acquire() == nil,
                      "Batch released a slot before GPU completion")
            other.forEach { pool.release($0) }
            textures.append(texture); leased.append((pool, slot))
        }
        let done = DispatchGroup(); done.enter()
        batch.command.addCompletedHandler { _ in done.leave() }
        try check(batch.commit() && callbacks == 3 && !batch.commit(), "Batch submitted more than once or missed display callbacks")
        try check(done.wait(timeout: .now() + 5) == .success && batch.command.status == .completed && batch.command.error == nil,
                  "Multi-display batch did not complete")
        for (index, texture) in textures.enumerated() {
            var bytes = [UInt8](repeating: 0, count: 8 * 8 * 4)
            bytes.withUnsafeMutableBytes {
                texture.getBytes($0.baseAddress!, bytesPerRow: 8 * 4, from: MTLRegionMake2D(0, 0, 8, 8), mipmapLevel: 0)
            }
            let expected: [[UInt8]] = [[0,0,255,255], [0,255,0,255], [255,0,0,255]]
            try check(Array(bytes.prefix(4)) == expected[index], "One display pass overwrote another target")
            let (pool, held) = leased[index]
            let slots = [pool.acquire(), pool.acquire(), pool.acquire()].compactMap { $0 }
            try check(slots.count == 3 && slots.contains(held), "Batch completion lost a display slot")
            slots.forEach { pool.release($0) }
        }
        let abandoned = MetalFramePool(device: resources.device)
        autoreleasepool {
            let dropped = MetalFrameBatch()!
            for _ in 0..<3 { dropped.add(pool: abandoned, slot: abandoned.acquire()!) {} }
        }
        let returned = [abandoned.acquire(), abandoned.acquire(), abandoned.acquire()].compactMap { $0 }
        try check(returned.count == 3, "Unsubmitted batch kept slots forever")
        returned.forEach { abandoned.release($0) }
    }
}
