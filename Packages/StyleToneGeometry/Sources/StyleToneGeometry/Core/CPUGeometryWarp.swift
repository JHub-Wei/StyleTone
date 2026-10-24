import Foundation
import StyleToneCore
import StyleToneImaging

/// CPU reference backend for the mesh warp.
///
/// This backend is intentionally simple and deterministic: it converts the
/// source through `ColorPipeline` into extended linear sRGB, evaluates the same
/// triangle mapping as the Metal mesh, bilinearly samples with clamp-to-edge
/// addressing and encodes the result back into the source colour space.
///
/// It exists for tests, simulators and as a fallback when Metal is unavailable.
/// It is not the 30 fps path; use ``MetalGeometryWarp`` for interactive frames
/// on device.
public struct CPUGeometryWarp: GeometryWarpBackend {
    public let identifier = "geometry.cpu"
    public let isGPUAccelerated = false

    public init() {}

    /// Warps an image on the CPU.
    public func warp(
        _ image: ImageAsset,
        field: WarpField,
        configuration: GeometryWarpConfiguration
    ) throws -> ImageAsset {
        try Task.checkCancellation()
        try field.validate()

        let width = image.pixelSize.width
        let height = image.pixelSize.height
        guard width > 0, height > 0 else {
            throw GeometryError.imageTooSmall(width: width, height: height)
        }
        if configuration.allowsIdentityShortcut, field.isZero() {
            return image
        }

        let pipeline = ColorPipeline()
        let source = try pipeline.linearize(image)
        guard source.width == width, source.height == height else {
            throw GeometryError.commandEncodingFailed
        }

        var destination = [SIMD4<Float>](
            repeating: SIMD4<Float>(0, 0, 0, 0),
            count: width * height
        )

        for y in 0 ..< height {
            try Task.checkCancellation()
            let normalizedY = (Float(y) + 0.5) / Float(height)
            let destinationRow = y * width
            for x in 0 ..< width {
                let normalizedX = (Float(x) + 0.5) / Float(width)
                let sourcePosition = MeshWarpSampler.sourcePosition(
                    for: SIMD2<Float>(normalizedX, normalizedY),
                    field: field
                )
                destination[destinationRow + x] = BilinearSampler.sample(
                    source.pixels,
                    width: source.width,
                    height: source.height,
                    at: sourcePosition
                )
            }
        }

        let linear = try LinearImage(width: width, height: height, pixels: destination)
        return try pipeline.makeImage(
            from: linear,
            colorSpace: ImageColorSpace.detect(image.colorSpace)
        )
    }
}
