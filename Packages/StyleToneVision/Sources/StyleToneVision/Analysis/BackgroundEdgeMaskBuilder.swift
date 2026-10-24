import Foundation
import StyleToneCore
import StyleToneImaging

/// Result of the background-structure model.
struct BackgroundEdgeMaskResult {
    let mask: MaskBuffer
    let edgeRatio: Double
    let lineRatio: Double
}

/// Builds the background edge / straight-line mask used for background
/// protection during warping.
///
/// The model combines an adaptive Sobel threshold with long horizontal and
/// vertical runs. Long runs catch door frames, floor tiles and table edges;
/// the raw gradient term keeps diagonal and curved structures. Pixels inside
/// the person mask are suppressed so clothing texture does not become a
/// background constraint.
struct BackgroundEdgeMaskBuilder {
    struct Configuration: Sendable, Equatable {
        /// Absolute gradient floor; prevents flat images from producing noise.
        var minimumGradient: Float
        /// Fraction of the image a run must span to count as a straight line.
        var lineRunFraction: Double
        /// Dilation radius for line and edge stamps, in pixels.
        var dilationRadius: Int
        /// Longest edge of the working buffer; larger inputs are sampled down.
        var maximumWorkingDimension: Int

        init(
            minimumGradient: Float = 0.02,
            lineRunFraction: Double = 1.0 / 12.0,
            dilationRadius: Int = 1,
            maximumWorkingDimension: Int = 512
        ) {
            self.minimumGradient = min(max(minimumGradient, 0), 2)
            self.lineRunFraction = min(max(lineRunFraction, 0.01), 0.5)
            self.dilationRadius = min(max(dilationRadius, 0), 3)
            self.maximumWorkingDimension = min(max(maximumWorkingDimension, 64), 4096)
        }
    }

    let configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func build(image: ImageAsset) throws -> BackgroundEdgeMaskResult {
        let linear = try ColorPipeline().linearize(image)
        return try build(linearImage: linear, personMask: nil)
    }

    func build(
        linearImage: LinearImage,
        personMask: MaskBuffer?
    ) throws -> BackgroundEdgeMaskResult {
        let inputSize = PixelSize(width: linearImage.width, height: linearImage.height)
        let workingImage = try Self.downsample(
            linearImage,
            maximumDimension: configuration.maximumWorkingDimension
        )
        let workingSize = PixelSize(width: workingImage.width, height: workingImage.height)
        let workingPersonMask: MaskBuffer?
        if let personMask,
           personMask.width == inputSize.width,
           personMask.height == inputSize.height,
           workingSize != inputSize {
            workingPersonMask = try? MaskResampler.resample(personMask, to: workingSize)
        } else {
            workingPersonMask = personMask
        }

        let result = try buildWorking(
            linearImage: workingImage,
            personMask: workingPersonMask
        )
        guard workingSize != inputSize else { return result }
        let mask = try MaskResampler.resample(result.mask, to: inputSize)
        return BackgroundEdgeMaskResult(
            mask: mask,
            edgeRatio: result.edgeRatio,
            lineRatio: result.lineRatio
        )
    }

    private func buildWorking(
        linearImage: LinearImage,
        personMask: MaskBuffer?
    ) throws -> BackgroundEdgeMaskResult {
        let width = linearImage.width
        let height = linearImage.height
        guard width > 0, height > 0 else {
            throw StyleToneError.invalidMask
        }
        guard width >= 3, height >= 3 else {
            let mask = try MaskBuffer(
                width: width,
                height: height,
                bytes: Data(repeating: 0, count: width * height)
            )
            return BackgroundEdgeMaskResult(mask: mask, edgeRatio: 0, lineRatio: 0)
        }

        var luma = [Float](repeating: 0, count: width * height)
        for index in 0 ..< luma.count {
            // Linear Rec. 709 luma is enough for edge/line geometry: the
            // threshold is adaptive and the mask is normalized afterwards.
            let pixel = linearImage.pixels[index]
            luma[index] = 0.2126 * pixel.x + 0.7152 * pixel.y + 0.0722 * pixel.z
        }
        try Task.checkCancellation()

        var gx = [Float](repeating: 0, count: width * height)
        var gy = [Float](repeating: 0, count: width * height)
        var magnitude = [Float](repeating: 0, count: width * height)
        var histogram = [Int](repeating: 0, count: 256)

        for y in 1 ..< height - 1 {
            if y.isMultiple(of: 64) {
                try Task.checkCancellation()
            }
            let row = y * width
            for x in 1 ..< width - 1 {
                let index = row + x
                let topLeft = luma[index - width - 1]
                let top = luma[index - width]
                let topRight = luma[index - width + 1]
                let left = luma[index - 1]
                let right = luma[index + 1]
                let bottomLeft = luma[index + width - 1]
                let bottom = luma[index + width]
                let bottomRight = luma[index + width + 1]

                let horizontal = (topRight + 2 * right + bottomRight)
                    - (topLeft + 2 * left + bottomLeft)
                let vertical = (bottomLeft + 2 * bottom + bottomRight)
                    - (topLeft + 2 * top + topRight)
                gx[index] = horizontal
                gy[index] = vertical
                let value = (horizontal * horizontal + vertical * vertical).squareRoot()
                magnitude[index] = value
                let bin = min(255, max(0, Int((value / 2 * 255).rounded())))
                histogram[bin] += 1
            }
        }

        let otsuBin = otsuThreshold(histogram: histogram)
        var threshold = Double(otsuBin) / 255 * 2
        if threshold < Double(configuration.minimumGradient) {
            threshold = thresholdFromTopFraction(histogram: histogram, fraction: 0.05)
            threshold = max(threshold, Double(configuration.minimumGradient))
        }
        let directionalThreshold = threshold * 1.10

        var edgeMask = [Bool](repeating: false, count: width * height)
        var lineMask = [Bool](repeating: false, count: width * height)
        var edgeCount = 0
        var lineCount = 0

        for index in 0 ..< magnitude.count where magnitude[index] >= Float(threshold) {
            edgeMask[index] = true
            edgeCount += 1
        }
        try Task.checkCancellation()

        let horizontalMinimumRun = max(8, Int(Double(width) * configuration.lineRunFraction))
        let verticalMinimumRun = max(8, Int(Double(height) * configuration.lineRunFraction))

        for y in 1 ..< height - 1 {
            if y.isMultiple(of: 64) {
                try Task.checkCancellation()
            }
            let row = y * width
            var runStart = -1
            for x in 1 ..< width - 1 {
                let index = row + x
                let isLine = abs(gy[index]) >= Float(directionalThreshold)
                    && abs(gy[index]) > abs(gx[index])
                if isLine, runStart < 0 {
                    runStart = x
                } else if !isLine, runStart >= 0 {
                    markHorizontalRun(
                        start: runStart,
                        end: x - 1,
                        y: y,
                        minimumRun: horizontalMinimumRun,
                        width: width,
                        mask: &lineMask
                    )
                    runStart = -1
                }
            }
            if runStart >= 0 {
                markHorizontalRun(
                    start: runStart,
                    end: width - 2,
                    y: y,
                    minimumRun: horizontalMinimumRun,
                    width: width,
                    mask: &lineMask
                )
            }
        }

        for x in 1 ..< width - 1 {
            if x.isMultiple(of: 64) {
                try Task.checkCancellation()
            }
            var runStart = -1
            for y in 1 ..< height - 1 {
                let index = y * width + x
                let isLine = abs(gx[index]) >= Float(directionalThreshold)
                    && abs(gx[index]) > abs(gy[index])
                if isLine, runStart < 0 {
                    runStart = y
                } else if !isLine, runStart >= 0 {
                    markVerticalRun(
                        start: runStart,
                        end: y - 1,
                        x: x,
                        minimumRun: verticalMinimumRun,
                        width: width,
                        mask: &lineMask
                    )
                    runStart = -1
                }
            }
            if runStart >= 0 {
                markVerticalRun(
                    start: runStart,
                    end: height - 2,
                    x: x,
                    minimumRun: verticalMinimumRun,
                    width: width,
                    mask: &lineMask
                )
            }
        }

        for index in 0 ..< lineMask.count where lineMask[index] {
            lineCount += 1
        }

        let dilatedEdges = dilate(
            edgeMask,
            width: width,
            height: height,
            radius: configuration.dilationRadius
        )
        let dilatedLines = dilate(
            lineMask,
            width: width,
            height: height,
            radius: configuration.dilationRadius + 1
        )

        var values = [Float](repeating: 0, count: width * height)
        let hasPersonMask = personMask?.width == width && personMask?.height == height
        for index in 0 ..< values.count {
            let personWeight: Float
            if hasPersonMask, let mask = personMask {
                personWeight = 1 - 0.95 * (Float(mask.bytes[index]) / 255)
            } else {
                personWeight = 1
            }
            values[index] = max(dilatedEdges[index] * 0.85, dilatedLines[index]) * personWeight
        }

        let blurred = boxBlur(values, width: width, height: height, radius: 1)
        var bytes = [UInt8](repeating: 0, count: width * height)
        for index in 0 ..< bytes.count {
            let value = min(max(blurred[index], 0), 1)
            bytes[index] = UInt8(min(max(Int((value * 255).rounded()), 0), 255))
        }

        let mask = try MaskBuffer(width: width, height: height, bytes: Data(bytes))
        let pixelCount = Double(width * height)
        return BackgroundEdgeMaskResult(
            mask: mask,
            edgeRatio: pixelCount > 0 ? Double(edgeCount) / pixelCount : 0,
            lineRatio: pixelCount > 0 ? Double(lineCount) / pixelCount : 0
        )
    }

    private static func downsample(
        _ image: LinearImage,
        maximumDimension: Int
    ) throws -> LinearImage {
        let longEdge = max(image.width, image.height)
        guard longEdge > maximumDimension else { return image }
        let scale = Double(maximumDimension) / Double(longEdge)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        var pixels = [SIMD4<Float>](repeating: SIMD4<Float>(0, 0, 0, 0), count: width * height)
        for y in 0 ..< height {
            if y.isMultiple(of: 64) {
                try Task.checkCancellation()
            }
            let sourceY = min(image.height - 1, y * image.height / height)
            let sourceRow = sourceY * image.width
            let destinationRow = y * width
            for x in 0 ..< width {
                let sourceX = min(image.width - 1, x * image.width / width)
                pixels[destinationRow + x] = image.pixels[sourceRow + sourceX]
            }
        }
        return try LinearImage(width: width, height: height, pixels: pixels)
    }

    private func markHorizontalRun(
        start: Int,
        end: Int,
        y: Int,
        minimumRun: Int,
        width: Int,
        mask: inout [Bool]
    ) {
        guard end - start + 1 >= minimumRun else { return }
        let row = y * width
        for x in start ... end {
            mask[row + x] = true
        }
    }

    private func markVerticalRun(
        start: Int,
        end: Int,
        x: Int,
        minimumRun: Int,
        width: Int,
        mask: inout [Bool]
    ) {
        guard end - start + 1 >= minimumRun else { return }
        for y in start ... end {
            mask[y * width + x] = true
        }
    }

    private func dilate(
        _ mask: [Bool],
        width: Int,
        height: Int,
        radius: Int
    ) -> [Float] {
        var horizontal = [Float](repeating: 0, count: mask.count)
        guard radius > 0 else {
            for index in 0 ..< mask.count {
                horizontal[index] = mask[index] ? 1 : 0
            }
            return horizontal
        }

        for y in 0 ..< height {
            let row = y * width
            for x in 0 ..< width {
                let start = max(0, x - radius)
                let end = min(width - 1, x + radius)
                var found = false
                for neighborX in start ... end where mask[row + neighborX] {
                    found = true
                    break
                }
                horizontal[row + x] = found ? 1 : 0
            }
        }

        var result = [Float](repeating: 0, count: mask.count)
        for y in 0 ..< height {
            let start = max(0, y - radius)
            let end = min(height - 1, y + radius)
            for x in 0 ..< width {
                var found = false
                for neighborY in start ... end where horizontal[neighborY * width + x] > 0 {
                    found = true
                    break
                }
                result[y * width + x] = found ? 1 : 0
            }
        }
        return result
    }

    private func boxBlur(
        _ values: [Float],
        width: Int,
        height: Int,
        radius: Int
    ) -> [Float] {
        guard radius > 0, width > 2, height > 2 else { return values }
        var horizontal = [Float](repeating: 0, count: values.count)
        for y in 0 ..< height {
            let row = y * width
            for x in 0 ..< width {
                let start = max(0, x - radius)
                let end = min(width - 1, x + radius)
                var sum: Float = 0
                for neighborX in start ... end {
                    sum += values[row + neighborX]
                }
                horizontal[row + x] = sum / Float(end - start + 1)
            }
        }
        var vertical = [Float](repeating: 0, count: values.count)
        for y in 0 ..< height {
            let start = max(0, y - radius)
            let end = min(height - 1, y + radius)
            for x in 0 ..< width {
                var sum: Float = 0
                for neighborY in start ... end {
                    sum += horizontal[neighborY * width + x]
                }
                vertical[y * width + x] = sum / Float(end - start + 1)
            }
        }
        return vertical
    }

    private func otsuThreshold(histogram: [Int]) -> Int {
        let total = histogram.reduce(0, +)
        guard total > 0 else { return 0 }
        var totalSum = 0.0
        for (index, count) in histogram.enumerated() {
            totalSum += Double(index * count)
        }
        var backgroundWeight = 0
        var backgroundSum = 0.0
        var bestVariance = 0.0
        var bestThreshold = 0

        for index in 0 ..< histogram.count {
            backgroundWeight += histogram[index]
            guard backgroundWeight > 0 else { continue }
            let foregroundWeight = total - backgroundWeight
            guard foregroundWeight > 0 else { break }
            backgroundSum += Double(index * histogram[index])
            let backgroundMean = backgroundSum / Double(backgroundWeight)
            let foregroundMean = (totalSum - backgroundSum) / Double(foregroundWeight)
            let difference = backgroundMean - foregroundMean
            let variance = Double(backgroundWeight) * Double(foregroundWeight) * difference * difference
            if variance > bestVariance {
                bestVariance = variance
                bestThreshold = index
            }
        }
        return bestThreshold
    }

    private func thresholdFromTopFraction(histogram: [Int], fraction: Double) -> Double {
        let total = histogram.reduce(0, +)
        guard total > 0 else { return 0 }
        let target = max(1, Int(Double(total) * min(max(fraction, 0.001), 0.5)))
        var cumulative = 0
        for index in stride(from: histogram.count - 1, through: 0, by: -1) {
            cumulative += histogram[index]
            if cumulative >= target {
                return Double(index) / 255 * 2
            }
        }
        return 0
    }
}
