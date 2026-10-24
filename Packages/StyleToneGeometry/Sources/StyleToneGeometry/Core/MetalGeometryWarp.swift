#if canImport(Metal)
import CoreGraphics
import Foundation
import Metal
import StyleToneCore
import StyleToneImaging

/// Metal mesh-warp backend.
///
/// One frame is encoded into a single command buffer:
///
/// 1. a **compute** kernel expands the `WarpField` into mesh vertices
///    (`position = grid`, `uv = grid - offset`);
/// 2. a **render** pass draws the indexed triangle mesh into an sRGB render
///    target with a linear clamp-to-edge sampler;
/// 3. on discrete-memory Macs a blit synchronises the managed texture before
///    the CPU reads it back.
///
/// The vertex grid is fixed in output space, so the mesh always covers the full
/// frame and the clamped sampler can never expose uninitialised or transparent
/// texels. Boundary pinning makes the outer ring exactly identity, which keeps
/// the frame edge stable in addition to the clamp.
///
/// The class is immutable after `init` (device, queue, pipelines and sampler)
/// and creates all per-frame resources locally, so concurrent calls are safe;
/// the unchecked `Sendable` conformance records that reasoning. The rendering
/// engine still serialises calls through its actor.
public final class MetalGeometryWarp: GeometryWarpBackend, @unchecked Sendable {
    public let identifier = "geometry.metal"
    public let isGPUAccelerated = true
    /// Human-readable device name for performance records.
    public let deviceName: String

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let buildPipeline: MTLComputePipelineState
    private let meshPipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState

    /// Returns a backend when Metal is available, otherwise `nil`.
    public static func makeIfAvailable() -> MetalGeometryWarp? {
        try? MetalGeometryWarp()
    }

    /// Creates the device, shader library, pipelines and sampler.
    ///
    /// - Throws: ``GeometryError`` when Metal is unavailable or a resource
    ///   cannot be created.
    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw GeometryError.metalUnavailable
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw GeometryError.resourceCreationFailed
        }

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            throw GeometryError.shaderCompilationFailed
        }
        guard let buildFunction = library.makeFunction(name: "geometryBuildMesh"),
              let vertexFunction = library.makeFunction(name: "geometryMeshVertex"),
              let fragmentFunction = library.makeFunction(name: "geometryMeshFragment")
        else {
            throw GeometryError.shaderCompilationFailed
        }

        let buildPipeline: MTLComputePipelineState
        do {
            buildPipeline = try device.makeComputePipelineState(function: buildFunction)
        } catch {
            throw GeometryError.pipelineCreationFailed
        }

        let renderDescriptor = MTLRenderPipelineDescriptor()
        renderDescriptor.label = "StyleTone.GeometryMesh"
        renderDescriptor.vertexFunction = vertexFunction
        renderDescriptor.fragmentFunction = fragmentFunction
        renderDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm_srgb
        renderDescriptor.colorAttachments[0].isBlendingEnabled = false

        let meshPipeline: MTLRenderPipelineState
        do {
            meshPipeline = try device.makeRenderPipelineState(descriptor: renderDescriptor)
        } catch {
            throw GeometryError.pipelineCreationFailed
        }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.label = "StyleTone.GeometryClampLinear"
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .notMipmapped
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.normalizedCoordinates = true
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw GeometryError.resourceCreationFailed
        }

        self.device = device
        self.commandQueue = commandQueue
        self.buildPipeline = buildPipeline
        self.meshPipeline = meshPipeline
        self.sampler = sampler
        self.deviceName = device.name
    }

    // MARK: - GeometryWarpBackend

    /// Warps an image and returns it as an exchange `ImageAsset`.
    public func warp(
        _ image: ImageAsset,
        field: WarpField,
        configuration: GeometryWarpConfiguration
    ) throws -> ImageAsset {
        try Task.checkCancellation()
        try field.validate()
        guard image.pixelSize.isPositive else {
            throw GeometryError.imageTooSmall(
                width: image.pixelSize.width,
                height: image.pixelSize.height
            )
        }
        if configuration.allowsIdentityShortcut, field.isZero() {
            return image
        }
        let texture = try renderTexture(
            image,
            field: field,
            configuration: configuration
        )
        return try makeImage(from: texture, colorSpace: image.colorSpace)
    }

    // MARK: - Preview / benchmark

    /// Renders one warped frame into an offscreen texture.
    ///
    /// This is the path to use for interactive preview (the caller can present
    /// the texture without a CPU readback) and for the performance harness.
    /// The command buffer is completed before this method returns, so the
    /// texture is safe to read or display.
    public func renderTexture(
        _ image: ImageAsset,
        field: WarpField,
        configuration: GeometryWarpConfiguration
    ) throws -> MTLTexture {
        try Task.checkCancellation()
        try field.validate()
        let width = image.pixelSize.width
        let height = image.pixelSize.height
        guard width > 0, height > 0 else {
            throw GeometryError.imageTooSmall(width: width, height: height)
        }
        let sourceTexture = try makeSourceTexture(from: image)
        let outputTexture = try makeOutputTexture(width: width, height: height)
        let offsetBuffer = try makeOffsetBuffer(field)
        let indexData = Self.makeIndexData(width: field.width, height: field.height)
        guard let indexBuffer = indexData.withUnsafeBytes({ raw -> MTLBuffer? in
            guard let baseAddress = raw.baseAddress else { return nil }
            return device.makeBuffer(
                bytes: baseAddress,
                length: raw.count,
                options: .storageModeShared
            )
        }) else {
            throw GeometryError.resourceCreationFailed
        }

        let vertexCount = field.vertexCount
        let vertexBuffer = device.makeBuffer(
            length: vertexCount * MemoryLayout<MeshVertex>.stride,
            options: .storageModePrivate
        )
        guard let vertexBuffer else {
            throw GeometryError.resourceCreationFailed
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw GeometryError.commandEncodingFailed
        }
        commandBuffer.label = "StyleTone.GeometryWarp"

        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw GeometryError.commandEncodingFailed
        }
        computeEncoder.label = "StyleTone.GeometryBuildMesh"
        computeEncoder.setComputePipelineState(buildPipeline)
        computeEncoder.setBuffer(offsetBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(vertexBuffer, offset: 0, index: 1)
        var uniforms = SIMD4<UInt32>(
            UInt32(field.width),
            UInt32(field.height),
            UInt32(width),
            UInt32(height)
        )
        withUnsafeBytes(of: &uniforms) { raw in
            if let baseAddress = raw.baseAddress {
                computeEncoder.setBytes(baseAddress, length: raw.count, index: 2)
            }
        }
        let threadsPerGroup = min(buildPipeline.maxTotalThreadsPerThreadgroup, vertexCount)
        let groupCount = (vertexCount + threadsPerGroup - 1) / threadsPerGroup
        computeEncoder.dispatchThreadgroups(
            MTLSize(width: groupCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadsPerGroup, height: 1, depth: 1)
        )
        computeEncoder.endEncoding()

        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = outputTexture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 1
        )

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            throw GeometryError.commandEncodingFailed
        }
        renderEncoder.label = "StyleTone.GeometryMesh"
        renderEncoder.setRenderPipelineState(meshPipeline)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(sourceTexture, index: 0)
        renderEncoder.setFragmentSamplerState(sampler, index: 0)
        renderEncoder.setViewport(
            MTLViewport(
                originX: 0,
                originY: 0,
                width: Double(width),
                height: Double(height),
                znear: 0,
                zfar: 1
            )
        )
        renderEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexData.count,
            indexType: .uint32,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0
        )
        renderEncoder.endEncoding()

        if outputTexture.storageMode == .managed {
            guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
                throw GeometryError.commandEncodingFailed
            }
            blitEncoder.synchronize(resource: outputTexture)
            blitEncoder.endEncoding()
        }

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if commandBuffer.error != nil {
            throw GeometryError.commandEncodingFailed
        }
        return outputTexture
    }

    // MARK: - Resource creation

    private func makeSourceTexture(from image: ImageAsset) throws -> MTLTexture {
        let width = image.pixelSize.width
        let height = image.pixelSize.height
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)

        let drew = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: image.colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .none
            context.setBlendMode(.copy)
            context.draw(
                image.cgImage,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        guard drew else {
            throw GeometryError.resourceCreationFailed
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw GeometryError.resourceCreationFailed
        }
        bytes.withUnsafeBytes { raw in
            if let baseAddress = raw.baseAddress {
                texture.replace(
                    region: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0,
                    withBytes: baseAddress,
                    bytesPerRow: bytesPerRow
                )
            }
        }
        return texture
    }

    private func makeOutputTexture(width: Int, height: Int) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw GeometryError.resourceCreationFailed
        }
        return texture
    }

    private func makeOffsetBuffer(_ field: WarpField) throws -> MTLBuffer {
        let offsets = field.offsets
        guard let buffer = offsets.withUnsafeBytes({ raw -> MTLBuffer? in
            guard let baseAddress = raw.baseAddress, raw.count > 0 else {
                return nil
            }
            return device.makeBuffer(
                bytes: baseAddress,
                length: raw.count,
                options: .storageModeShared
            )
        }) else {
            throw GeometryError.resourceCreationFailed
        }
        return buffer
    }

    private func makeImage(from texture: MTLTexture, colorSpace: CGColorSpace) throws -> ImageAsset {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        bytes.withUnsafeMutableBytes { raw in
            if let baseAddress = raw.baseAddress {
                texture.getBytes(
                    baseAddress,
                    bytesPerRow: bytesPerRow,
                    from: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0
                )
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else {
            throw GeometryError.resourceCreationFailed
        }
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw GeometryError.resourceCreationFailed
        }
        return ImageAsset(cgImage: cgImage, colorSpace: colorSpace)
    }

    private static func makeIndexData(width: Int, height: Int) -> [UInt32] {
        var indices: [UInt32] = []
        indices.reserveCapacity((width - 1) * (height - 1) * 6)
        for y in 0 ..< (height - 1) {
            for x in 0 ..< (width - 1) {
                let topLeft = UInt32(y * width + x)
                let topRight = topLeft + 1
                let bottomLeft = UInt32((y + 1) * width + x)
                let bottomRight = bottomLeft + 1
                // First triangle covers the top-left half of the cell, second
                // triangle the bottom-right half. MeshWarpSampler uses the same
                // diagonal.
                indices.append(topLeft)
                indices.append(topRight)
                indices.append(bottomLeft)
                indices.append(topRight)
                indices.append(bottomRight)
                indices.append(bottomLeft)
            }
        }
        return indices
    }

    // MARK: - Shader

    private struct MeshVertex {
        var position: SIMD2<Float>
        var uv: SIMD2<Float>
    }

    private static let shaderSource = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct MeshVertex {
        float2 position;
        float2 uv;
    };

    struct GeometryUniforms {
        // x = grid width, y = grid height, z = image width, w = image height.
        uint4 dimensions;
    };

    kernel void geometryBuildMesh(device const float2 *offsets [[buffer(0)]],
                                  device MeshVertex *vertices [[buffer(1)]],
                                  constant GeometryUniforms &uniforms [[buffer(2)]],
                                  uint index [[thread_position_in_grid]])
    {
        uint gridWidth = uniforms.dimensions.x;
        uint gridHeight = uniforms.dimensions.y;
        uint count = gridWidth * gridHeight;
        if (index >= count) {
            return;
        }
        uint x = index % gridWidth;
        uint y = index / gridWidth;
        float2 grid = float2(float(x), float(y))
            / float2(float(gridWidth - 1), float(gridHeight - 1));
        float2 offset = offsets[index];

        MeshVertex vertex;
        vertex.position = grid;
        vertex.uv = grid - offset;
        vertices[index] = vertex;
    }

    struct MeshVertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex MeshVertexOut geometryMeshVertex(uint vertexID [[vertex_id]],
                                            device const MeshVertex *vertices [[buffer(0)]])
    {
        MeshVertex vertex = vertices[vertexID];
        MeshVertexOut output;
        output.position = float4(vertex.position.x * 2.0 - 1.0,
                                 1.0 - vertex.position.y * 2.0,
                                 0.0,
                                 1.0);
        output.uv = vertex.uv;
        return output;
    }

    fragment float4 geometryMeshFragment(MeshVertexOut input [[stage_in]],
                                         texture2d<float> source [[texture(0)]],
                                         sampler clampSampler [[sampler(0)]])
    {
        return source.sample(clampSampler, input.uv);
    }
    """#
}
#endif
