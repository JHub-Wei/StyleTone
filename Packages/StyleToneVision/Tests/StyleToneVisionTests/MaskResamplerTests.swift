import Foundation
import XCTest
import StyleToneCore
@testable import StyleToneVision

final class MaskResamplerTests: XCTestCase {
    func testIdentityReturnsSameMask() throws {
        let mask = try MaskBuffer(width: 3, height: 2, bytes: Data([0, 64, 128, 255, 32, 16]))
        let resampled = try MaskResampler.resample(mask, to: PixelSize(width: 3, height: 2))
        XCTAssertEqual(resampled.width, 3)
        XCTAssertEqual(resampled.height, 2)
        XCTAssertEqual(resampled.bytes, mask.bytes)
    }

    func testUpscalesWithCorrectDimensions() throws {
        let mask = try MaskBuffer(width: 2, height: 2, bytes: Data([0, 255, 128, 64]))
        let resampled = try MaskResampler.resample(mask, to: PixelSize(width: 8, height: 8))
        XCTAssertEqual(resampled.width, 8)
        XCTAssertEqual(resampled.height, 8)
        XCTAssertEqual(resampled.bytes.count, 64)
        XCTAssertLessThan(resampled.value(x: 0, y: 0) ?? 255, 130)
        XCTAssertGreaterThan(resampled.value(x: 7, y: 0) ?? 0, 150)
    }

    func testDownscalesWithoutChangingRange() throws {
        var bytes = [UInt8](repeating: 0, count: 32 * 32)
        for index in bytes.indices {
            bytes[index] = UInt8(index % 256)
        }
        let mask = try MaskBuffer(width: 32, height: 32, bytes: Data(bytes))
        let resampled = try MaskResampler.resample(mask, to: PixelSize(width: 7, height: 5))
        XCTAssertEqual(resampled.width, 7)
        XCTAssertEqual(resampled.height, 5)
        XCTAssertEqual(resampled.bytes.count, 35)
    }

    func testInvalidTargetThrows() throws {
        let mask = try MaskBuffer(width: 2, height: 2, bytes: Data(repeating: 0, count: 4))
        XCTAssertThrowsError(try MaskResampler.resample(mask, to: PixelSize(width: 0, height: 4)))
    }
}
