import XCTest
import StyleToneCore
import StyleToneImaging
import StyleToneVision
import StyleToneGeometry
import StyleToneRetouch
import StyleToneLearning
import StyleTonePersistence
import StyleToneCommerce
import StyleToneUI

/// WP-00 linkage test: ensures every package product is linked into the app
/// test bundle. Feature tests belong to their own work packages.
final class ModuleLinkageTests: XCTestCase {
    func testAllModulesAreLinked() {
        XCTAssertEqual(StyleToneCoreModule.name, "StyleToneCore")
        XCTAssertEqual(StyleToneImagingModule.name, "StyleToneImaging")
        XCTAssertEqual(StyleToneVisionModule.name, "StyleToneVision")
        XCTAssertEqual(StyleToneGeometryModule.name, "StyleToneGeometry")
        XCTAssertEqual(StyleToneRetouchModule.name, "StyleToneRetouch")
        XCTAssertEqual(StyleToneLearningModule.name, "StyleToneLearning")
        XCTAssertEqual(StyleTonePersistenceModule.name, "StyleTonePersistence")
        XCTAssertEqual(StyleToneCommerceModule.name, "StyleToneCommerce")
        XCTAssertEqual(StyleToneUIModule.name, "StyleToneUI")
    }
}
