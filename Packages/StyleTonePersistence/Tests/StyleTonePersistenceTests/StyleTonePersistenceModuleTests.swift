import XCTest
@testable import StyleTonePersistence

final class StyleTonePersistenceModuleTests: XCTestCase {
    func testModuleName() {
        XCTAssertEqual(StyleTonePersistenceModule.name, "StyleTonePersistence")
    }
}
