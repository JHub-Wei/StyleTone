import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import StyleToneCore
import Vision

/// One person-segmentation pass over the analysis proxy.
struct PersonSegmentationOutcome {
    /// Mask at proxy resolution, or `nil` when no person is present.
    let mask: StyleToneCore.MaskBuffer?
    /// Fraction of pixels classified as person before any resampling.
    let coverage: Double
    let failed: Bool
}

/// Wraps `VNGeneratePersonSegmentationRequest`.
enum VisionPersonSegmenter {
    static func segment(
        in cgImage: CGImage,
        proxySize: StyleToneCore.PixelSize,
        configuration: VisionAnalysisConfiguration
    ) -> PersonSegmentationOutcome {
        guard configuration.personSegmentationEnabled else {
            return PersonSegmentationOutcome(mask: nil, coverage: 0, failed: false)
        }

        let request = VNGeneratePersonSegmentationRequest()
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        switch configuration.segmentationQuality {
        case .fast:
            request.qualityLevel = .fast
        case .balanced:
            request.qualityLevel = .balanced
        case .accurate:
            request.qualityLevel = .accurate
        }

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: CGImagePropertyOrientation.up,
            options: [:]
        )
        do {
            try handler.perform([request])
        } catch {
            return PersonSegmentationOutcome(mask: nil, coverage: 0, failed: true)
        }

        guard let observation = request.results?.first else {
            return PersonSegmentationOutcome(mask: nil, coverage: 0, failed: false)
        }

        guard let rawMask = makeMask(from: observation.pixelBuffer) else {
            return PersonSegmentationOutcome(mask: nil, coverage: 0, failed: true)
        }

        var personPixels = 0
        let bytes = rawMask.bytes
        for index in 0 ..< bytes.count where bytes[index] >= 128 {
            personPixels += 1
        }
        let coverage = rawMask.pixelCount > 0
            ? Double(personPixels) / Double(rawMask.pixelCount)
            : 0

        guard coverage >= configuration.minimumPersonCoverage else {
            return PersonSegmentationOutcome(mask: nil, coverage: coverage, failed: false)
        }

        do {
            let resized = try MaskResampler.resample(rawMask, to: proxySize)
            return PersonSegmentationOutcome(mask: resized, coverage: coverage, failed: false)
        } catch {
            return PersonSegmentationOutcome(mask: nil, coverage: coverage, failed: true)
        }
    }

    private static func makeMask(from pixelBuffer: CVPixelBuffer) -> StyleToneCore.MaskBuffer? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return nil }

        let status = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        guard status == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard bytesPerRow >= width else { return nil }
        let source = baseAddress.assumingMemoryBound(to: UInt8.self)

        var bytes = [UInt8](repeating: 0, count: width * height)
        for y in 0 ..< height {
            let sourceRow = source + y * bytesPerRow
            let destinationRow = y * width
            for x in 0 ..< width {
                bytes[destinationRow + x] = sourceRow[x]
            }
        }
        return try? StyleToneCore.MaskBuffer(
            width: width,
            height: height,
            bytes: Data(bytes)
        )
    }
}
