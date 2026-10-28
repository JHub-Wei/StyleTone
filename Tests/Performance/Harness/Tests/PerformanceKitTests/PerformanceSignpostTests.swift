import XCTest
@testable import PerformanceKit

final class PerformanceSignpostTests: XCTestCase {
    func testEveryEventHasAStableSignpostName() {
        for event in PerformanceSignpostEvent.allCases {
            XCTAssertFalse(event.rawValue.isEmpty)
            XCTAssertFalse(String(describing: event.staticName).isEmpty)
        }
        XCTAssertEqual(String(describing: PerformanceSignpostEvent.firstFrame.staticName), "first-frame")
        XCTAssertEqual(String(describing: PerformanceSignpostEvent.export.staticName), "export")
    }

    func testNoOpWrapperReturnsTheBodyValueOnEveryPlatform() {
        let signposter = PerformanceSignposter()
        let value = signposter.withInterval(.firstFrame) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testThrowingBodyPropagates() {
        struct TestError: Error {}
        let signposter = PerformanceSignposter()
        XCTAssertThrowsError(
            try signposter.withInterval(.export) { throw TestError() }
        )
    }
}
