import Foundation
import StyleToneUI
import XCTest

/// Offline behaviour: core work stays available, store calls degrade with a
/// retry/continue path, and passive offline is not turned into an error card.
final class OfflineCapabilityTests: XCTestCase {
    func testCoreFeaturesStayAvailableOffline() {
        XCTAssertTrue(OfflineCapability.coreIsOfflineReady)
        XCTAssertFalse(OfflineCapability.coreFeatures.isEmpty)

        for feature in OfflineCapability.coreFeatures {
            XCTAssertEqual(
                OfflineCapability.availability(of: feature, isOffline: true),
                .available,
                "\(feature) should work offline"
            )
        }

        let required: Set<AppFeature> = [
            .onboarding,
            .pairing,
            .calibration,
            .styleLearning,
            .styleProfiles,
            .editing,
            .previewRendering,
            .fullRendering,
            .exportRendering,
            .savingToPhotos,
            .sharing,
            .diagnostics,
        ]
        XCTAssertTrue(required.isSubset(of: Set(OfflineCapability.coreFeatures)))
    }

    func testOnlyStoreCallsRequireAConnection() {
        XCTAssertEqual(
            OfflineCapability.availability(of: .purchase, isOffline: true),
            .requiresConnection
        )
        XCTAssertEqual(
            OfflineCapability.availability(of: .restorePurchase, isOffline: true),
            .requiresConnection
        )
        XCTAssertEqual(
            OfflineCapability.availability(of: .productLoading, isOffline: true),
            .requiresConnection
        )

        for feature in OfflineCapability.networkFeatures {
            XCTAssertEqual(
                OfflineCapability.availability(of: feature, isOffline: false),
                .available
            )
        }
    }

    func testEveryFeatureIsClassified() {
        let all = Set(AppFeature.allCases)
        let core = Set(OfflineCapability.coreFeatures)
        let network = OfflineCapability.networkFeatures

        XCTAssertTrue(core.isDisjoint(with: network))
        XCTAssertEqual(core.union(network), all)
    }

    func testOfflineStateOffersARealWayForward() {
        let state = ErrorMapper.offline(context: .paywall)

        XCTAssertEqual(state.kind, .offline)
        XCTAssertEqual(state.severity, .notice)
        XCTAssertEqual(state.context, .paywall)
        XCTAssertEqual(state.diagnosticCode.rawValue, "ST-NET-001")
        XCTAssertTrue(state.recoveryActions.contains(.continueOffline))
        XCTAssertTrue(state.recoveryActions.contains(.retry))
        XCTAssertTrue(state.recoveryActions.contains(.dismiss))
        XCTAssertFalse(state.isSilent)
    }

    func testURLErrorMappingSeparatesOfflineFromTransientNetworkFailures() {
        let offlineCodes: [URLError.Code] = [
            .notConnectedToInternet,
            .networkConnectionLost,
            .dataNotAllowed,
            .internationalRoamingOff,
            .callIsActive,
        ]
        for code in offlineCodes {
            let error = URLError(code)
            XCTAssertTrue(ErrorMapper.isOffline(error), "\(code.rawValue)")
            let state = ErrorMapper.state(for: error, context: .paywall)
            XCTAssertEqual(state.kind, .offline, "\(code.rawValue)")
            XCTAssertTrue(state.recoveryActions.contains(.continueOffline))
            XCTAssertEqual(state.sourceCode, "URLError.\(code.rawValue)")
        }

        let timedOut = ErrorMapper.state(for: URLError(.timedOut), context: .paywall)
        XCTAssertEqual(timedOut.kind, .networkUnavailable)
        XCTAssertFalse(timedOut.recoveryActions.contains(.continueOffline))
        XCTAssertTrue(timedOut.recoveryActions.contains(.retry))
        XCTAssertFalse(ErrorMapper.isOffline(URLError(.timedOut)))
        XCTAssertFalse(ErrorMapper.isOffline(EdgeCaseOpaqueError()))
    }

    func testPassiveOfflineDoesNotCreateAnErrorCard() {
        let advisor = ErrorAdvisor.standard
        let conditions = DeviceConditions(
            isOffline: true,
            batteryLevel: 1,
            availableDiskBytes: 32_000_000_000
        )
        XCTAssertTrue(advisor.advisories(for: conditions).isEmpty)
    }

    func testStoreOfflineFailureKeepsTheEditorUsable() {
        let state = ErrorMapper.state(
            for: PurchaseFailureReason.offline,
            context: .paywall
        )

        XCTAssertEqual(state.kind, .offline)
        XCTAssertEqual(state.severity, .notice)
        XCTAssertTrue(state.recoveryActions.contains(.continueOffline))
        XCTAssertTrue(state.recoveryActions.contains(.retry))
        XCTAssertEqual(
            OfflineCapability.availability(of: .editing, isOffline: true),
            .available
        )
        XCTAssertEqual(
            OfflineCapability.availability(of: .exportRendering, isOffline: true),
            .available
        )
    }

    func testEveryPurchaseReasonMapsToAStableState() {
        let expectations: [PurchaseFailureReason: ErrorKind] = [
            .offline: .offline,
            .cancelled: .cancelled,
            .productUnavailable: .purchaseUnavailable,
            .paymentNotAllowed: .purchaseUnavailable,
            .verificationFailed: .purchaseVerificationFailed,
            .purchaseFailed: .purchaseFailed,
            .restoreFailed: .restoreFailed,
            .unknown: .unknown,
        ]
        XCTAssertEqual(expectations.count, PurchaseFailureReason.allCases.count)

        for reason in PurchaseFailureReason.allCases {
            let state = ErrorMapper.state(for: reason, context: .paywall)
            XCTAssertEqual(state.kind, expectations[reason], "reason \(reason)")
            XCTAssertEqual(state.sourceCode, "PURCHASE_\(reason.rawValue.uppercased())")
            if reason == .cancelled {
                XCTAssertTrue(state.isSilent)
            } else {
                XCTAssertFalse(state.recoveryActions.isEmpty)
            }
        }
    }

    func testCancelledPurchaseDoesNotShowAnError() {
        let state = ErrorMapper.state(for: PurchaseFailureReason.cancelled)
        XCTAssertTrue(state.isSilent)
        XCTAssertTrue(state.recoveryActions.isEmpty)
        XCTAssertFalse(state.severity == .recoverable)
    }
}
