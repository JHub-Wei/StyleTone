import XCTest
@testable import PerformanceKit

final class PerformanceScenarioTests: XCTestCase {
    func testCatalogIdentifiersAreUnique() {
        let ids = PerformanceScenario.catalog.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testContractTargetsMatchContractsSection10() {
        let expected: [String: Double] = [
            "launch.coldStart": 2.0,
            "preview.firstFrame": 1.5,
            "preview.sliderResponse": 0.1,
            "preview.frameTime": 1.0 / 30.0,
            "learning.fivePairs": 90,
            "export.twelveMegapixel": 6,
            "preview.memoryPeak": 300,
            "export.memoryPeak": 500
        ]
        for (id, target) in expected {
            let scenario = try? XCTUnwrap(PerformanceScenario.scenario(id: id))
            XCTAssertEqual(scenario?.contractTarget ?? -1, target, accuracy: 1e-9, id)
        }
    }

    func testEveryCatalogUnitMatchesDirection() {
        for scenario in PerformanceScenario.catalog {
            switch scenario.unit {
            case .seconds, .megabytes, .count:
                XCTAssertEqual(scenario.direction, .lowerIsBetter, scenario.id)
            case .framesPerSecond:
                XCTAssertEqual(scenario.direction, .higherIsBetter, scenario.id)
            }
            XCTAssertGreaterThanOrEqual(scenario.minimumSamples, 1, scenario.id)
            XCTAssertGreaterThanOrEqual(scenario.noiseFloor, 0, scenario.id)
        }
    }

    func testUnknownScenarioReturnsNil() {
        XCTAssertNil(PerformanceScenario.scenario(id: "does.not.exist"))
    }
}
