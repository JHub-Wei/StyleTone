import Foundation
import StyleToneCore

// MARK: - Ground-truth structure

/// One straight background structure line known to the scene generator.
///
/// Coordinates are normalized with a top-left origin, matching
/// `BackgroundStructureLine` in the geometry module. For a vertical line,
/// `position` is `x` and `start`/`end` are `y`; for a horizontal line,
/// `position` is `y` and `start`/`end` are `x`.
public struct PortraitGroundTruthLine: Codable, Sendable, Equatable {
    public enum Orientation: String, Codable, Sendable, CaseIterable {
        case vertical
        case horizontal
    }

    public var orientation: Orientation
    public var position: Double
    public var start: Double
    public var end: Double
    public var label: String

    public init(
        orientation: Orientation,
        position: Double,
        start: Double,
        end: Double,
        label: String
    ) {
        self.orientation = orientation
        self.position = position
        self.start = start
        self.end = end
        self.label = label
    }

    /// Length of the declared extent in normalized units.
    public var span: Double {
        max(0, end - start)
    }
}

/// Ground-truth geometry of one rendered person.
///
/// Values are normalized image coordinates, so the same layout can be checked
/// against the rendered pixels and against the `PortraitAnalysis` handed to the
/// pipeline.
public struct PortraitSubjectGeometry: Sendable, Equatable {
    public var role: PortraitSubjectRole
    public var skinTone: SkinToneBand
    public var bodyType: PortraitBodyType
    public var occlusion: PortraitOcclusion
    public var faceBox: NormalizedRect
    public var faceCenter: NormalizedPoint
    public var personBox: NormalizedRect
    public var faceLandmarks: [FaceLandmarkKind: [NormalizedPoint]]
    public var bodyJoints: [BodyJointKind: NormalizedPoint]
    public var isFrontmost: Bool

    public init(
        role: PortraitSubjectRole,
        skinTone: SkinToneBand,
        bodyType: PortraitBodyType,
        occlusion: PortraitOcclusion,
        faceBox: NormalizedRect,
        faceCenter: NormalizedPoint,
        personBox: NormalizedRect,
        faceLandmarks: [FaceLandmarkKind: [NormalizedPoint]],
        bodyJoints: [BodyJointKind: NormalizedPoint],
        isFrontmost: Bool
    ) {
        self.role = role
        self.skinTone = skinTone
        self.bodyType = bodyType
        self.occlusion = occlusion
        self.faceBox = faceBox
        self.faceCenter = faceCenter
        self.personBox = personBox
        self.faceLandmarks = faceLandmarks
        self.bodyJoints = bodyJoints
        self.isFrontmost = isFrontmost
    }
}

/// Everything the quality metrics need to know about a rendered sample.
///
/// The masks are ground truth produced by the renderer, not detector output.
/// Using ground truth here isolates algorithm regressions from detector noise;
/// detector accuracy is covered by the analysis test suites instead.
public struct PortraitGroundTruth: Sendable, Equatable {
    public var imageSize: PixelSize
    public var personMask: MaskBuffer
    public var skinMask: MaskBuffer
    public var backgroundEdgeMask: MaskBuffer
    public var lines: [PortraitGroundTruthLine]
    /// Subjects in draw order (back to front).
    public var subjects: [PortraitSubjectGeometry]
    public var primaryFaceBox: NormalizedRect?

    public init(
        imageSize: PixelSize,
        personMask: MaskBuffer,
        skinMask: MaskBuffer,
        backgroundEdgeMask: MaskBuffer,
        lines: [PortraitGroundTruthLine],
        subjects: [PortraitSubjectGeometry],
        primaryFaceBox: NormalizedRect?
    ) {
        self.imageSize = imageSize
        self.personMask = personMask
        self.skinMask = skinMask
        self.backgroundEdgeMask = backgroundEdgeMask
        self.lines = lines
        self.subjects = subjects
        self.primaryFaceBox = primaryFaceBox
    }

    /// The front-most (primary) subject geometry.
    public var primarySubject: PortraitSubjectGeometry? {
        subjects.first { $0.role == .primary } ?? subjects.last
    }
}

/// A fully rendered synthetic portrait: pixels, pipeline analysis and ground
/// truth. No file or network access is involved.
public struct PortraitScene: Sendable {
    public var spec: PortraitSampleSpec
    public var pixels: PixelBuffer
    public var analysis: PortraitAnalysis
    public var groundTruth: PortraitGroundTruth

    public init(
        spec: PortraitSampleSpec,
        pixels: PixelBuffer,
        analysis: PortraitAnalysis,
        groundTruth: PortraitGroundTruth
    ) {
        self.spec = spec
        self.pixels = pixels
        self.analysis = analysis
        self.groundTruth = groundTruth
    }

    /// Short identifier for reports and artifact names.
    public var id: String { spec.id }
}

// MARK: - Mask helpers

/// Small, allocation-explicit mask operations shared by the renderer and the
/// quality metrics.
public enum MaskOperations {
    /// Raw bytes of a mask.
    public static func bytes(_ mask: MaskBuffer) -> [UInt8] {
        [UInt8](mask.bytes)
    }

    /// Builds a mask from row-major bytes.
    public static func make(
        width: Int,
        height: Int,
        values: [UInt8]
    ) throws -> MaskBuffer {
        guard values.count == width * height else {
            throw GoldenSupportError.invalidPixelBuffer(
                expectedByteCount: width * height,
                actualByteCount: values.count
            )
        }
        return try MaskBuffer(width: width, height: height, bytes: Data(values))
    }

    /// Coverage of pixels above zero, in `0...1`.
    public static func coverage(_ mask: MaskBuffer) -> Double {
        guard mask.pixelCount > 0 else { return 0 }
        var count = 0
        for value in mask.bytes where value > 0 {
            count += 1
        }
        return Double(count) / Double(mask.pixelCount)
    }

    /// Number of pixels above zero.
    public static func nonzeroCount(_ mask: MaskBuffer) -> Int {
        mask.bytes.reduce(0) { $1 > 0 ? $0 + 1 : $0 }
    }

    /// Binary dilation with a square structuring element.
    ///
    /// The implementation is a separable running maximum, so the cost is
    /// `O(width * height)` independent of the radius.
    public static func dilated(_ mask: MaskBuffer, radius: Int) throws -> MaskBuffer {
        let radius = max(0, radius)
        guard radius > 0 else { return mask }
        let width = mask.width
        let height = mask.height
        let source = bytes(mask)
        var horizontal = [UInt8](repeating: 0, count: width * height)
        for y in 0 ..< height {
            for x in 0 ..< width {
                var value: UInt8 = 0
                let lower = max(0, x - radius)
                let upper = min(width - 1, x + radius)
                for sample in lower ... upper where source[y * width + sample] > value {
                    value = source[y * width + sample]
                }
                horizontal[y * width + x] = value
            }
        }
        var output = [UInt8](repeating: 0, count: width * height)
        for y in 0 ..< height {
            let lower = max(0, y - radius)
            let upper = min(height - 1, y + radius)
            for x in 0 ..< width {
                var value: UInt8 = 0
                for sample in lower ... upper {
                    let candidate = horizontal[sample * width + x]
                    if candidate > value {
                        value = candidate
                    }
                }
                output[y * width + x] = value
            }
        }
        return try make(width: width, height: height, values: output)
    }

    /// Binary erosion with a square structuring element (border treated as 0).
    public static func eroded(_ mask: MaskBuffer, radius: Int) throws -> MaskBuffer {
        let radius = max(0, radius)
        guard radius > 0 else { return mask }
        let width = mask.width
        let height = mask.height
        let source = bytes(mask)
        var horizontal = [UInt8](repeating: 0, count: width * height)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let lower = x - radius
                let upper = x + radius
                guard lower >= 0, upper < width else {
                    horizontal[y * width + x] = 0
                    continue
                }
                var value: UInt8 = 255
                for sample in lower ... upper {
                    let candidate = source[y * width + sample]
                    if candidate < value { value = candidate }
                }
                horizontal[y * width + x] = value
            }
        }
        var output = [UInt8](repeating: 0, count: width * height)
        for y in 0 ..< height {
            let lower = y - radius
            let upper = y + radius
            guard lower >= 0, upper < height else {
                continue
            }
            for x in 0 ..< width {
                var value: UInt8 = 255
                for sample in lower ... upper {
                    let candidate = horizontal[sample * width + x]
                    if candidate < value { value = candidate }
                }
                output[y * width + x] = value
            }
        }
        return try make(width: width, height: height, values: output)
    }

    /// Intersection-over-union of two same-size masks.
    public static func intersectionOverUnion(_ first: MaskBuffer, _ second: MaskBuffer) -> Double {
        guard first.width == second.width, first.height == second.height else { return 0 }
        var intersection = 0
        var union = 0
        let firstBytes = bytes(first)
        let secondBytes = bytes(second)
        for index in 0 ..< firstBytes.count {
            let inFirst = firstBytes[index] > 0
            let inSecond = secondBytes[index] > 0
            if inFirst && inSecond { intersection += 1 }
            if inFirst || inSecond { union += 1 }
        }
        return union == 0 ? 1 : Double(intersection) / Double(union)
    }

    /// One-pixel boundary of a binary mask (4-connectivity).
    public static func boundaryPoints(_ mask: MaskBuffer) -> [(x: Int, y: Int)] {
        let width = mask.width
        let height = mask.height
        let source = bytes(mask)
        var points: [(x: Int, y: Int)] = []
        for y in 0 ..< height {
            for x in 0 ..< width where source[y * width + x] > 0 {
                let left = x == 0 ? 0 : source[y * width + x - 1]
                let right = x == width - 1 ? 0 : source[y * width + x + 1]
                let top = y == 0 ? 0 : source[(y - 1) * width + x]
                let bottom = y == height - 1 ? 0 : source[(y + 1) * width + x]
                if left == 0 || right == 0 || top == 0 || bottom == 0 {
                    points.append((x, y))
                }
            }
        }
        return points
    }
}
