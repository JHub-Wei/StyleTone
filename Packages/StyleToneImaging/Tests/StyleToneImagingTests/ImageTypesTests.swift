import CoreGraphics
import XCTest
import StyleToneCore
import StyleToneImaging

final class ImageTypesTests: XCTestCase {
    func testFileFormatDetection() {
        XCTAssertEqual(ImageFileFormat.detect("public.heic"), .heic)
        XCTAssertEqual(ImageFileFormat.detect("public.heif"), .heic)
        XCTAssertEqual(ImageFileFormat.detect("public.heif-standard"), .heic)
        XCTAssertEqual(ImageFileFormat.detect("public.jpeg"), .jpeg)
        XCTAssertEqual(ImageFileFormat.detect("public.png"), .png)
        XCTAssertNil(ImageFileFormat.detect("public.tiff"))
        XCTAssertNil(ImageFileFormat.detect("com.compuserve.gif"))
    }

    func testExportFormatExtensions() {
        XCTAssertEqual(ExportFormat.heic.typeIdentifier, "public.heic")
        XCTAssertEqual(ExportFormat.jpeg.typeIdentifier, "public.jpeg")
        XCTAssertEqual(ExportFormat.heic.filenameExtension, "heic")
        XCTAssertEqual(ExportFormat.jpeg.filenameExtension, "jpg")
    }

    func testColorSpaceDetection() {
        XCTAssertEqual(ImageColorSpace.detect(ImageColorSpace.sRGB.cgColorSpace), .sRGB)
        XCTAssertEqual(ImageColorSpace.detect(ImageColorSpace.displayP3.cgColorSpace), .displayP3)
        XCTAssertEqual(ImageColorSpace.sRGB.displayName, "sRGB IEC61966-2.1")
        XCTAssertEqual(ImageColorSpace.displayP3.displayName, "Display P3")
    }

    func testLoadOptionsClampValues() {
        let options = ImageLoadOptions(maximumLongEdge: 0, minimumLongEdge: -5)
        XCTAssertEqual(options.maximumLongEdge, 1)
        XCTAssertEqual(options.minimumLongEdge, 1)
        XCTAssertNil(ImageLoadOptions.fullResolution.maximumLongEdge)
    }

    func testWriteOptionsClampQuality() {
        XCTAssertEqual(
            ImageWriteOptions(format: .jpeg, quality: 2, colorSpace: .sRGB).quality,
            1
        )
        XCTAssertEqual(
            ImageWriteOptions(format: .jpeg, quality: -1, colorSpace: .sRGB).quality,
            0
        )
        XCTAssertEqual(
            ImageWriteOptions(format: .jpeg, quality: .nan, colorSpace: .sRGB).quality,
            0.92
        )
        XCTAssertEqual(ImageWriteOptions().format, .heic)
        XCTAssertEqual(ImageWriteOptions().colorSpace, .sRGB)
    }
}
