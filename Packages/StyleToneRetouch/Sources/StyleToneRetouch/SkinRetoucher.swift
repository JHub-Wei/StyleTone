import Foundation
import StyleToneCore

/// Skin retouch engine implementing ``RetouchRendering`` and
/// ``BlemishRemoving``.
///
/// The value is immutable and `Sendable`; every call performs its work on a
/// detached user-initiated task, so callers never run the pixel pipeline on the
/// main thread. The engine keeps no state, which makes undo the UI layer's
/// responsibility as required by the contract.
public struct SkinRetoucher: Sendable {
    public let configuration: SkinRetouchConfiguration

    public init(configuration: SkinRetouchConfiguration = .standard) {
        self.configuration = configuration
    }
}

extension SkinRetoucher: RetouchRendering {
    /// Applies smoothing and/or evenness inside the analysis skin mask.
    ///
    /// - Smoothing uses a self-guided filter plus high-frequency separation,
    ///   retaining ``SkinRetouchConfiguration/fineTextureRetain`` of the pore
    ///   band at full strength.
    /// - Evenness redistributes regional luma and chroma with a hard per-pixel
    ///   limit, so average brightness, hue and saturation are preserved.
    /// - If `analysis.skinMask` is missing, has a different size, is empty, or
    ///   is entirely covered by the facial-feature guard, the original asset is
    ///   returned unchanged.
    public func retouch(
        _ image: ImageAsset,
        analysis: PortraitAnalysis,
        parameters: SkinParameters
    ) async throws -> ImageAsset {
        let configuration = configuration
        let work = Task.detached(priority: .userInitiated) {
            try SkinRetouchPipeline(configuration: configuration).render(
                image,
                analysis: analysis,
                parameters: parameters
            )
        }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }
}
