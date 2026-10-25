import Foundation
import GoldenSupport
import StyleToneCore
import TestShared
import XCTest
@testable import StyleToneUI

// MARK: - Fixtures

@MainActor
enum SkinToolsTestFactory {
    static func image(
        size: PixelSize = PixelSize(width: 96, height: 128),
        color: RGB8 = .midGray
    ) throws -> ImageAsset {
        try MockImageAssetFactory.solid(color: color, size: size)
    }

    static func analysis(
        for image: ImageAsset,
        faceCount: Int = 1,
        includesBody: Bool = true,
        includesMasks: Bool = true
    ) throws -> PortraitAnalysis {
        try MockPortraitAnalysisFactory.portrait(
            size: image.pixelSize,
            faceCount: faceCount,
            includesBody: includesBody,
            includesMasks: includesMasks
        )
    }

    static func model(
        image: ImageAsset,
        analysis: PortraitAnalysis,
        retoucher: any RetouchRendering,
        blemishRemover: any BlemishRemoving,
        configuration: SkinToolsConfiguration = .immediate()
    ) -> SkinToolsViewModel {
        SkinToolsViewModel(
            image: image,
            analysis: analysis,
            retoucher: retoucher,
            blemishRemover: blemishRemover,
            configuration: configuration
        )
    }
}

// MARK: - Retouch spy

actor SkinToolsRetouchSpy: RetouchRendering {
    enum Step: Sendable {
        case success(ImageAsset)
        case failure(StyleToneError)
    }

    private var steps: [Step]
    private(set) var parameters: [SkinParameters] = []
    private(set) var analysisSizes: [PixelSize] = []

    init(steps: [Step] = []) {
        self.steps = steps
    }

    func retouch(
        _ image: ImageAsset,
        analysis: PortraitAnalysis,
        parameters: SkinParameters
    ) async throws -> ImageAsset {
        self.parameters.append(parameters)
        self.analysisSizes.append(analysis.imageSize)

        guard !steps.isEmpty else { return image }
        switch steps.removeFirst() {
        case let .success(output):
            return output
        case let .failure(error):
            throw error
        }
    }

    func enqueue(_ step: Step) {
        steps.append(step)
    }

    func callCount() -> Int {
        parameters.count
    }

    func lastParameters() -> SkinParameters? {
        parameters.last
    }

    func recordedAnalysisSizes() -> [PixelSize] {
        analysisSizes
    }
}

// MARK: - Blemish spy

actor SkinToolsBlemishSpy: BlemishRemoving {
    enum Step: Sendable {
        case success(ImageAsset)
        case failure(StyleToneError)
    }

    private var steps: [Step]
    private(set) var points: [BlemishPoint] = []
    private(set) var analysisSizes: [PixelSize] = []

    init(steps: [Step] = []) {
        self.steps = steps
    }

    func removeBlemish(
        _ image: ImageAsset,
        at point: BlemishPoint,
        analysis: PortraitAnalysis
    ) async throws -> ImageAsset {
        self.points.append(point)
        self.analysisSizes.append(analysis.imageSize)

        guard !steps.isEmpty else { return image }
        switch steps.removeFirst() {
        case let .success(output):
            return output
        case let .failure(error):
            throw error
        }
    }

    func enqueue(_ step: Step) {
        steps.append(step)
    }

    func callCount() -> Int {
        points.count
    }

    func recordedPoints() -> [BlemishPoint] {
        points
    }

    func recordedAnalysisSizes() -> [PixelSize] {
        analysisSizes
    }
}

// MARK: - Cancellation gate

/// A retoucher that suspends until the test releases or cancels it. This makes
/// the in-flight/cancel test deterministic without sleeping: the render task
/// yields until `release()` or the task's cancellation reaches the loop.
actor SkinToolsGatedRetoucher: RetouchRendering {
    private let output: ImageAsset
    private var started = false
    private var released = false

    init(output: ImageAsset) {
        self.output = output
    }

    func retouch(
        _ image: ImageAsset,
        analysis: PortraitAnalysis,
        parameters: SkinParameters
    ) async throws -> ImageAsset {
        started = true
        while !released {
            try Task.checkCancellation()
            await Task.yield()
        }
        return output
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func release() {
        released = true
    }
}
