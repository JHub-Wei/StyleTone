import XCTest
@testable import GoldenSupport

final class ColorScienceTests: XCTestCase {
    func testSRGBTransferFunctionRoundTrips() {
        for value in 0...255 {
            let encoded = Double(value) / 255.0
            let linear = ColorScience.srgbToLinear(encoded)
            let restored = ColorScience.linearToSRGB(linear)
            XCTAssertEqual(restored * 255.0, Double(value), accuracy: 1e-6)
        }
    }

    func testKnownLabValues() {
        let white = ColorScience.lab(RGB8.white)
        XCTAssertEqual(white.l, 100, accuracy: 0.01)
        XCTAssertEqual(white.a, 0, accuracy: 0.02)
        XCTAssertEqual(white.b, 0, accuracy: 0.02)

        let red = ColorScience.lab(RGB8(red: 255, green: 0, blue: 0))
        XCTAssertEqual(red.l, 53.2408, accuracy: 0.05)
        XCTAssertEqual(red.a, 80.0925, accuracy: 0.05)
        XCTAssertEqual(red.b, 67.2032, accuracy: 0.05)

        let green = ColorScience.lab(RGB8(red: 0, green: 255, blue: 0))
        XCTAssertEqual(green.l, 87.7347, accuracy: 0.05)
        XCTAssertEqual(green.a, -86.1827, accuracy: 0.05)
        XCTAssertEqual(green.b, 83.1793, accuracy: 0.05)

        let blue = ColorScience.lab(RGB8(red: 0, green: 0, blue: 255))
        XCTAssertEqual(blue.l, 32.2970, accuracy: 0.05)
        XCTAssertEqual(blue.a, 79.1875, accuracy: 0.05)
        XCTAssertEqual(blue.b, -107.8602, accuracy: 0.05)

        let gray = ColorScience.lab(RGB8.midGray)
        XCTAssertEqual(gray.l, 53.585, accuracy: 0.05)
        XCTAssertEqual(gray.a, 0, accuracy: 0.05)
        XCTAssertEqual(gray.b, 0, accuracy: 0.05)
    }

    func testXYZLabRoundTrip() {
        let colors: [RGB8] = [
            .black, .white, .midGray,
            RGB8(red: 0xE8, green: 0xD5, blue: 0xC4),
            RGB8(red: 0x2F, green: 0x4F, blue: 0x6F),
            RGB8(red: 0x7B, green: 0x4B, blue: 0x2A)
        ]
        for color in colors {
            let lab = ColorScience.lab(color)
            let xyz = ColorScience.xyz(lab)
            let roundTripped = ColorScience.lab(xyz)
            XCTAssertEqual(roundTripped.l, lab.l, accuracy: 1e-6)
            XCTAssertEqual(roundTripped.a, lab.a, accuracy: 1e-6)
            XCTAssertEqual(roundTripped.b, lab.b, accuracy: 1e-6)
        }
    }

    /// Reference pairs from Sharma, Wu & Dalal (2005), "The CIEDE2000
    /// Color-Difference Formula", Table 1.
    func testCIEDE2000ReferencePairs() {
        let pairs: [(LabColor, LabColor, Double)] = [
            (LabColor(l: 50, a: 2.6772, b: -79.7751), LabColor(l: 50, a: 0, b: -82.7485), 2.0425),
            (LabColor(l: 50, a: 3.1571, b: -77.2803), LabColor(l: 50, a: 0, b: -82.7485), 2.8615),
            (LabColor(l: 50, a: 2.8361, b: -74.0200), LabColor(l: 50, a: 0, b: -82.7485), 3.4412),
            (LabColor(l: 50, a: -1.3802, b: -84.2814), LabColor(l: 50, a: 0, b: -82.7485), 1.0000),
            (LabColor(l: 50, a: -1.1848, b: -84.8006), LabColor(l: 50, a: 0, b: -82.7485), 1.0000),
            (LabColor(l: 50, a: -0.9009, b: -85.5211), LabColor(l: 50, a: 0, b: -82.7485), 1.0000),
            (LabColor(l: 50, a: 2.5, b: 0), LabColor(l: 73, a: 25, b: -18), 27.1492),
            (LabColor(l: 50, a: 2.5, b: 0), LabColor(l: 61, a: -5, b: 29), 22.8977),
            (LabColor(l: 60.2574, a: -34.0099, b: 36.2677),
             LabColor(l: 60.4626, a: -34.1751, b: 39.4387), 1.2644),
            (LabColor(l: 90.9257, a: -0.5406, b: -0.9208),
             LabColor(l: 88.6381, a: -0.8985, b: -0.7239), 1.5381)
        ]

        for (first, second, expected) in pairs {
            XCTAssertEqual(
                ColorScience.deltaE00(first, second),
                expected,
                accuracy: 1e-4,
                "ΔE00 \(first) / \(second)"
            )
            XCTAssertEqual(
                ColorScience.deltaE00(second, first),
                expected,
                accuracy: 1e-4,
                "ΔE00 must be symmetric"
            )
        }
    }

    func testIdenticalColoursHaveZeroDifference() {
        let color = ColorScience.lab(RGB8(red: 12, green: 34, blue: 56))
        XCTAssertEqual(ColorScience.deltaE00(color, color), 0, accuracy: 1e-12)
    }

    func testBlackWhiteDifferenceIsAboutOneHundred() {
        XCTAssertEqual(
            ColorScience.deltaE00(RGB8.black, RGB8.white),
            100,
            accuracy: 0.5
        )
    }

    func testContrastRatioExtremes() {
        XCTAssertEqual(RGB8.black.contrastRatio(with: .white), 21, accuracy: 0.01)
        XCTAssertEqual(RGB8.midGray.contrastRatio(with: .midGray), 1, accuracy: 1e-9)
    }
}
