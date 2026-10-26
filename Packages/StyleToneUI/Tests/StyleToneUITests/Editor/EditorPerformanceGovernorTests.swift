import XCTest
@testable import StyleToneUI

final class EditorPerformanceGovernorTests: XCTestCase {
    func testStartsWithFullQuality() {
        let governor = EditorPerformanceGovernor()
        XCTAssertEqual(governor.level, .full)
        XCTAssertEqual(governor.previewLongEdge, 1280)
        XCTAssertFalse(governor.isDegraded)
    }

    func testTwoSlowPreviewsDegradeOneTier() {
        var governor = EditorPerformanceGovernor()
        governor.record(duration: 0.5, quality: .preview)
        XCTAssertEqual(governor.level, .full)

        governor.record(duration: 0.5, quality: .preview)
        XCTAssertEqual(governor.level, .reduced)
        XCTAssertEqual(governor.previewLongEdge, 960)
        XCTAssertTrue(governor.isDegraded)
    }

    func testSlowStreakContinuesToMinimalAndStops() {
        var governor = EditorPerformanceGovernor()
        for _ in 0..<2 {
            governor.record(duration: 0.5, quality: .preview)
        }
        for _ in 0..<2 {
            governor.record(duration: 0.5, quality: .preview)
        }
        XCTAssertEqual(governor.level, .minimal)
        XCTAssertEqual(governor.previewLongEdge, 640)

        governor.record(duration: 0.5, quality: .preview)
        governor.record(duration: 0.5, quality: .preview)
        XCTAssertEqual(governor.level, .minimal)
    }

    func testFullQualitySamplesDoNotDegrade() {
        var governor = EditorPerformanceGovernor()
        for _ in 0..<10 {
            governor.record(duration: 5.0, quality: .full)
        }
        XCTAssertEqual(governor.level, .full)
        XCTAssertEqual(governor.previewSampleCount, 0)
    }

    func testThreeFastPreviewsRecoverOneTier() {
        var governor = EditorPerformanceGovernor(level: .minimal)
        for _ in 0..<3 {
            governor.record(duration: 0.02, quality: .preview)
        }
        XCTAssertEqual(governor.level, .reduced)

        for _ in 0..<3 {
            governor.record(duration: 0.02, quality: .preview)
        }
        XCTAssertEqual(governor.level, .full)
    }

    func testMediumDurationsResetBothStreaks() {
        var governor = EditorPerformanceGovernor()
        governor.record(duration: 0.5, quality: .preview)
        governor.record(duration: 0.2, quality: .preview)
        governor.record(duration: 0.5, quality: .preview)
        XCTAssertEqual(governor.level, .full)
    }

    func testResetReturnsToFull() {
        var governor = EditorPerformanceGovernor(level: .minimal)
        governor.reset()
        XCTAssertEqual(governor.level, .full)
        XCTAssertEqual(governor.previewSampleCount, 0)
    }
}
