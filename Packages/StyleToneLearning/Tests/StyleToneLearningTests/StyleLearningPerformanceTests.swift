import Foundation
import StyleToneCore
import TestShared
import XCTest
@testable import StyleToneLearning

final class StyleLearningPerformanceTests: XCTestCase {
    private func makeEngine() -> StyleLearningEngine {
        StyleLearningEngine(dateProvider: FixedDateProvider())
    }

    func testFivePairLearningStaysUnderNinetySeconds() async throws {
        let pairs = try SyntheticPairFactory.pairs(
            count: 5,
            edit: SyntheticEdit(
                exposure: 1.10,
                redGain: 1.03,
                saturation: 1.10,
                blurRadius: 2
            )
        )
        let start = Date()
        let result = try await makeEngine().learn(
            StyleLearningRequest(samples: pairs)
        )
        let duration = Date().timeIntervalSince(start)

        XCTAssertEqual(result.profile.pairCount, 5)
        XCTAssertLessThan(duration, 90)
        record(duration, label: "5 pairs")
    }

    func testEightPairLearningStaysUnderOneHundredFiftySeconds() async throws {
        let pairs = try SyntheticPairFactory.pairs(
            count: 8,
            edit: SyntheticEdit(
                exposure: 1.12,
                redGain: 1.04,
                blueGain: 0.97,
                saturation: 1.12,
                blurRadius: 2
            )
        )
        let start = Date()
        let result = try await makeEngine().learn(
            StyleLearningRequest(samples: pairs)
        )
        let duration = Date().timeIntervalSince(start)

        XCTAssertEqual(result.profile.pairCount, 8)
        XCTAssertLessThan(duration, 150)
        record(duration, label: "8 pairs")
    }

    private func record(_ duration: TimeInterval, label: String) {
        let attachment = XCTAttachment(
            string: String(format: "%@ learning duration: %.3f s", label, duration)
        )
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
