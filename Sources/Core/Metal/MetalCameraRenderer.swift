import Metal
import MetalKit
import CoreVideo
import os.log

private let logger = Logger(subsystem: "com.kevinjones.Kinetriq", category: "MetalCameraRenderer")

/// Renders a CVPixelBuffer (BGRA) as a full-screen textured quad via Metal.
///
/// Usage:
/// 1. Create with `MetalCameraRenderer()`.
/// 2. Call `setup(view:)` once when the `MTKView` is available (from UIViewRepresentable).
/// 3. Call `update(pixelBuffer:)` from any thread for each new camera frame.
final class MetalCameraRenderer: NSObject, MTKViewDelegate {

    // MARK: - Metal State

    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?

    // MARK: - Frame Buffer (camera queue → draw thread)

    private var pendingBuffer: CVPixelBuffer?
    private let bufferLock = NSLock()

    // MARK: - Init

    override init() {
        super.init()
        guard let dev = MTLCreateSystemDefaultDevice() else {
            logger.error("Metal not available on this device")
            return
        }
        device = dev
        commandQueue = dev.makeCommandQueue()

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, dev, nil, &cache)
        textureCache = cache

        buildPipeline(device: dev)
        logger.info("MetalCameraRenderer initialized")
    }

    // MARK: - View Setup

    /// Attach this renderer to an MTKView. Called once from UIViewRepresentable.makeUIView.
    func setup(view: MTKView) {
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 30
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.delegate = self
    }

    // MARK: - Frame Update (any thread)

    func update(pixelBuffer: CVPixelBuffer) {
        bufferLock.lock()
        pendingBuffer = pixelBuffer
        bufferLock.unlock()
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        bufferLock.lock()
        let buffer = pendingBuffer
        bufferLock.unlock()

        guard let buffer,
              let device,
              let commandQueue,
              let pipeline,
              let textureCache,
              let drawable = view.currentDrawable,
              let passDesc = view.currentRenderPassDescriptor else { return }

        // CVPixelBuffer → MTLTexture via cache (zero-copy)
        let width  = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        var cvTex: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, buffer, nil,
            .bgra8Unorm, width, height, 0, &cvTex
        )
        guard let cvTex, let texture = CVMetalTextureGetTexture(cvTex) else { return }

        guard let cmdBuf = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc) else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()

        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    // MARK: - Private

    private func buildPipeline(device: MTLDevice) {
        guard let library = device.makeDefaultLibrary(),
              let vertFn = library.makeFunction(name: "cameraVertex"),
              let fragFn = library.makeFunction(name: "cameraFragment") else {
            logger.error("Could not load Metal shader functions")
            return
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.label = "CameraPipeline"
        desc.vertexFunction = vertFn
        desc.fragmentFunction = fragFn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            logger.error("Pipeline creation failed: \(error.localizedDescription)")
        }
    }
}
