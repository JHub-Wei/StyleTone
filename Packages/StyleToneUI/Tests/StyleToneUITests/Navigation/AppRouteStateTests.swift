import XCTest
import StyleToneUI

final class AppRouteStateTests: XCTestCase {
    func testInitialStateShowsEditorRoot() {
        let state = AppRouteState()
        XCTAssertEqual(state.selectedTab, .editor)
        XCTAssertNil(state.presentedSheet)
        XCTAssertEqual(state.path(for: .editor), [])
        XCTAssertEqual(state.path(for: .style), [])
        XCTAssertEqual(state.path(for: .settings), [])
    }

    func testEveryRouteHasValidMetadata() {
        XCTAssertEqual(Set(AppRoute.allCases.map(\.rawValue)).count, AppRoute.allCases.count)
        for route in AppRoute.allCases {
            XCTAssertTrue(route.titleKey.isValid, "Invalid title key for \(route)")
            XCTAssertTrue(route.accessibilityID.isValid, "Invalid identifier for \(route)")
            XCTAssertFalse(route.systemImage.isEmpty)
        }
    }

    func testTabRootRoutesAreDistinct() {
        let roots = AppTab.allCases.map(\.rootRoute)
        XCTAssertEqual(Set(roots).count, AppTab.allCases.count)
        for tab in AppTab.allCases {
            XCTAssertTrue(tab.accessibilityID.isValid)
            XCTAssertTrue(tab.titleKey.isValid)
        }
    }

    func testPushAndPopWithinTab() {
        var state = AppRouteState()
        XCTAssertTrue(state.push(.pairing))
        XCTAssertTrue(state.push(.onboarding))
        XCTAssertEqual(state.path(for: .editor), [.pairing, .onboarding])
        XCTAssertEqual(state.topRoute(for: .editor), .onboarding)

        XCTAssertEqual(state.pop(), .onboarding)
        XCTAssertEqual(state.pop(), .pairing)
        XCTAssertNil(state.pop())
        XCTAssertEqual(state.path(for: .editor), [])
    }

    func testPopToRoot() {
        var state = AppRouteState()
        XCTAssertFalse(state.popToRoot())

        _ = state.push(.pairing)
        _ = state.push(.styleProfile)
        XCTAssertTrue(state.popToRoot())
        XCTAssertEqual(state.path(for: .editor), [])
        XCTAssertFalse(state.popToRoot())
    }

    func testPushRejectsSheetRoutes() {
        var state = AppRouteState()
        XCTAssertFalse(state.push(.paywall))
        XCTAssertFalse(state.push(.export))
        XCTAssertNil(state.presentedSheet)
    }

    func testPresentRejectsPushRoutes() {
        var state = AppRouteState()
        XCTAssertFalse(state.present(.pairing))
        XCTAssertNil(state.presentedSheet)
    }

    func testPushRejectsTabRoot() {
        var state = AppRouteState()
        XCTAssertFalse(state.push(.editor))
        XCTAssertEqual(state.path(for: .editor), [])

        state.select(.style)
        XCTAssertFalse(state.push(.calibration))
        XCTAssertEqual(state.path(for: .style), [])
    }

    func testDuplicateConsecutivePushIsRejected() {
        var state = AppRouteState()
        XCTAssertTrue(state.push(.pairing))
        XCTAssertFalse(state.push(.pairing))
        XCTAssertEqual(state.path(for: .editor), [.pairing])
    }

    func testPathDepthIsCapped() {
        var state = AppRouteState()
        state.setPath(Array(repeating: .pairing, count: 40), for: .editor)
        XCTAssertEqual(state.path(for: .editor).count, AppRouteState.maxPathDepth)
        XCTAssertFalse(state.push(.onboarding))
    }

    func testSetPathDropsSheetRoutes() {
        var state = AppRouteState()
        state.setPath([.pairing, .paywall, .onboarding], for: .editor)
        XCTAssertEqual(state.path(for: .editor), [.pairing, .onboarding])
    }

    func testTabPathsAreIsolated() {
        var state = AppRouteState()
        XCTAssertTrue(state.push(.pairing))
        state.select(.style)
        XCTAssertTrue(state.push(.styleProfile))

        XCTAssertEqual(state.path(for: .editor), [.pairing])
        XCTAssertEqual(state.path(for: .style), [.styleProfile])
        XCTAssertEqual(state.path(for: .settings), [])
        XCTAssertEqual(state.selectedTab, .style)
    }

    func testSelectDoesNotClearPaths() {
        var state = AppRouteState()
        _ = state.push(.pairing)
        state.select(.settings)
        XCTAssertEqual(state.path(for: .editor), [.pairing])
        state.select(.editor)
        XCTAssertEqual(state.path(for: .editor), [.pairing])
    }

    func testSheetLifecycle() {
        var state = AppRouteState()
        XCTAssertTrue(state.present(.paywall))
        XCTAssertEqual(state.presentedSheet, .paywall)
        state.dismissSheet()
        XCTAssertNil(state.presentedSheet)

        XCTAssertTrue(state.present(.export))
        XCTAssertEqual(state.presentedSheet, .export)
    }

    func testNavigateDispatchesByPresentation() {
        var state = AppRouteState()
        XCTAssertTrue(state.navigate(.pairing))
        XCTAssertEqual(state.topRoute(for: .editor), .pairing)

        XCTAssertTrue(state.navigate(.paywall))
        XCTAssertEqual(state.presentedSheet, .paywall)
        XCTAssertEqual(state.topRoute(for: .editor), .pairing)
    }

    func testNavigateToTabRootSelectsTabAndClearsPath() {
        var state = AppRouteState()
        _ = state.push(.pairing)
        _ = state.push(.onboarding)

        XCTAssertTrue(state.navigate(.calibration))
        XCTAssertEqual(state.selectedTab, .style)
        XCTAssertEqual(state.path(for: .style), [])

        XCTAssertTrue(state.navigate(.settings))
        XCTAssertEqual(state.selectedTab, .settings)

        XCTAssertTrue(state.navigate(.editor))
        XCTAssertEqual(state.selectedTab, .editor)
        XCTAssertEqual(state.path(for: .editor), [])
    }

    func testEveryRouteCanBeNavigatedAndReset() {
        for route in AppRoute.allCases {
            var state = AppRouteState()
            XCTAssertTrue(state.navigate(route), "Could not navigate to \(route)")

            if route.presentation == .sheet {
                XCTAssertEqual(state.presentedSheet, route)
                state.dismissSheet()
                XCTAssertNil(state.presentedSheet)
            } else if let tab = AppTab.allCases.first(where: { $0.rootRoute == route }) {
                XCTAssertEqual(state.selectedTab, tab)
                XCTAssertNil(state.topRoute(for: tab))
            } else {
                XCTAssertEqual(state.topRoute(for: state.selectedTab), route)
                XCTAssertTrue(state.popToRoot())
                XCTAssertEqual(state.path(for: state.selectedTab), [])
            }
        }
    }

    func testRepeatedTabSwitchingKeepsStateStable() {
        var state = AppRouteState()
        for _ in 0..<20 {
            for tab in AppTab.allCases {
                state.select(tab)
                XCTAssertEqual(state.selectedTab, tab)
                XCTAssertEqual(state.path(for: tab), [])
            }
        }
    }
}
