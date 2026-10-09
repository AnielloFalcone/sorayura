import Foundation
import Metal

/// Immutable, thread-safe Metal objects shared by all desktop renderers.
final class FilamentResources: @unchecked Sendable {
    static let shared: FilamentResources? = {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return FilamentResources(device: device)
    }()

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState

    private init?(device: MTLDevice) {
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct Out { float4 position [[position]]; float4 color; float edge; float soft; };
        vertex Out filamentVertex(const device float *v [[buffer(0)]], uint id [[vertex_id]]) {
            uint i = id * 8;
            Out o; o.position = float4(v[i], v[i+1], 0, 1);
            o.color = float4(v[i+2], v[i+3], v[i+4], v[i+5]); o.edge = v[i+6]; o.soft = v[i+7]; return o;
        }
        fragment float4 filamentFragment(Out in [[stage_in]]) {
            float falloff = exp(-4.5 * in.edge * in.edge) * (1.0 - smoothstep(0.8, 1.0, abs(in.edge)));
            return float4(in.color.rgb, in.color.a * mix(1.0, falloff, in.soft));
        }
        """
        guard let commandQueue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: source, options: nil),
              let vertex = library.makeFunction(name: "filamentVertex"),
              let fragment = library.makeFunction(name: "filamentFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.device = device
        self.commandQueue = commandQueue
        self.pipeline = pipeline
    }
}

/// Each renderer owns three slots. A completion returns its exact slot, so GPU
/// completion order cannot cause the CPU to overwrite a buffer still in use.
final class MetalFramePool: @unchecked Sendable {
    private let device: MTLDevice
    private let lock = NSLock()
    private var available = [0, 1, 2]
    private var buffers: [MTLBuffer?] = [nil, nil, nil]

    init(device: MTLDevice) { self.device = device }

    func acquire() -> Int? {
        lock.lock(); defer { lock.unlock() }
        return available.popLast()
    }

    func release(_ slot: Int) {
        lock.lock(); defer { lock.unlock() }
        precondition(buffers.indices.contains(slot) && !available.contains(slot))
        available.append(slot)
    }

    func buffer(for slot: Int, length: Int) -> MTLBuffer? {
        lock.lock(); defer { lock.unlock() }
        precondition(buffers.indices.contains(slot) && !available.contains(slot))
        guard length > 0, length <= device.maxBufferLength else { return nil }
        if let buffer = buffers[slot], buffer.length >= length { return buffer }
        // Grow geometrically only when this leased slot needs more room.
        var capacity = 32 * 1024
        while capacity < length { capacity *= 2 }
        guard let next = device.makeBuffer(length: min(capacity, device.maxBufferLength), options: .storageModeShared) else { return nil }
        next.label = "Wallpaper vertices · slot \(slot)"
        buffers[slot] = next
        return next
    }
}
