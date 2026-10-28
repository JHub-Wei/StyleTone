import XCTest
@testable import StyleToneRetouch

final class EvennessSafetyTests: XCTestCase {
    func testSilhouetteGuardProtectsOnlyBoundaryBand() {
        let width = 16
        let height = 16
        var alpha = [UInt8](repeating: 0, count: width * height)
        for y in 4 ..< 12 {
            for x in 4 ..< 12 {
                alpha[y * width + x] = 255
            }
        }

        let guardMask = SilhouetteGuard.make(
            alpha: alpha,
            width: width,
            height: height,
            radius: 2
        )

        XCTAssertEqual(guardMask.count, alpha.count)
        XCTAssertEqual(guardMask[8 * width + 8], 255)
        XCTAssertEqual(guardMask[4 * width + 8], 0)
        XCTAssertEqual(guardMask[8 * width + 4], 0)
        XCTAssertEqual(guardMask[0], 0)
    }

    func testHeadroomClampKeepsChannelsOffClippingRails() {
        let clamped = RetouchMath.clampHeadroom(SIMD3<Float>(1.2, -0.2, 0.5))
        XCTAssertEqual(clamped.x, 0.94)
        XCTAssertEqual(clamped.y, 0.003)
        XCTAssertEqual(clamped.z, 0.5)
    }
}
