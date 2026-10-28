import Foundation
import StyleToneCore
import StyleToneUI
import XCTest

/// Permission and storage edges: denied/restricted Photos, out-of-space,
/// read-only volumes and a storage preflight that never guesses.
final class PermissionAndStorageTests: XCTestCase {
    // MARK: - Photos permission

    func testPhotoLibraryAccessMapsToPermissionStates() {
        let expectations: [(PhotoLibraryAccess, ErrorKind?)] = [
            (.notDetermined, nil),
            (.authorized, nil),
            (.limited, nil),
            (.denied, .photoPermissionDenied),
            (.restricted, .photoPermissionRestricted),
            (.unavailable, .photoLibraryUnavailable),
        ]
        XCTAssertEqual(expectations.count, PhotoLibraryAccess.allCases.count)

        for (access, expected) in expectations {
            let state = ErrorMapper.state(for: access, context: .export)
            XCTAssertEqual(state?.kind, expected, "access \(access)")
            if let state {
                XCTAssertEqual(state.context, .export)
                XCTAssertEqual(
                    state.sourceCode,
                    "PHOTO_ACCESS_\(access.rawValue.uppercased())"
                )
                XCTAssertFalse(state.recoveryActions.isEmpty)
            }
        }
    }

    func testDeniedPhotosOffersSettingsAndShare() {
        let state = ErrorMapper.state(for: PhotoLibraryAccess.denied)
        XCTAssertEqual(state?.kind, .photoPermissionDenied)
        XCTAssertEqual(
            state?.recoveryActions,
            [.openSettings, .shareInstead, .retry, .dismiss]
        )
        XCTAssertEqual(state?.diagnosticCode.rawValue, "ST-PERM-001")
        XCTAssertTrue(state?.message.text.contains("Settings") ?? false)
    }

    func testRestrictedPhotosDoesNotOfferAnImpossibleSettingsTrip() {
        let state = ErrorMapper.state(for: PhotoLibraryAccess.restricted)
        XCTAssertEqual(state?.kind, .photoPermissionRestricted)
        XCTAssertFalse(state?.recoveryActions.contains(.openSettings) ?? true)
        XCTAssertTrue(state?.recoveryActions.contains(.shareInstead) ?? false)
        XCTAssertTrue(state?.recoveryActions.contains(.dismiss) ?? false)
    }

    func testPhotoLibraryErrorsMapWithoutLeakingTheFile() {
        let cases: [(ExportLibraryError, ErrorKind)] = [
            (.permissionDenied, .photoPermissionDenied),
            (.permissionRestricted, .photoPermissionRestricted),
            (.saveFailed, .exportLibrarySaveFailed),
            (.unavailable, .photoLibraryUnavailable),
        ]
        for (error, expected) in cases {
            let state = ErrorMapper.state(for: error)
            XCTAssertEqual(state.kind, expected)
            XCTAssertEqual(state.sourceCode, error.code)
            XCTAssertFalse(state.title.text.contains("/"))
        }
    }

    // MARK: - Cocoa and POSIX

    func testOutOfSpaceFromCocoaAndPOSIXMapsToStorageFull() {
        let cocoa = EdgeCaseFixtures.cocoaError(.fileWriteOutOfSpace)
        let cocoaState = ErrorMapper.state(for: cocoa, context: .export)
        XCTAssertEqual(cocoaState.kind, .storageFull)
        XCTAssertEqual(
            cocoaState.sourceCode,
            "NSCocoaErrorDomain.\(CocoaError.Code.fileWriteOutOfSpace.rawValue)"
        )
        XCTAssertEqual(cocoaState.recoveryActions, [.freeUpSpace, .retry, .dismiss])
        XCTAssertEqual(cocoaState.diagnosticCode.rawValue, "ST-STOR-002")

        let posix = NSError(domain: NSPOSIXErrorDomain, code: 28)
        let posixState = ErrorMapper.state(for: posix)
        XCTAssertEqual(posixState.kind, .storageFull)
        XCTAssertEqual(posixState.sourceCode, "NSPOSIXErrorDomain.28")
    }

    func testReadOnlyAndPermissionFileErrorsMapToStorageUnavailable() {
        let cocoaCodes: [CocoaError.Code] = [
            .fileWriteVolumeReadOnly,
            .fileWriteNoPermission,
            .fileReadNoPermission,
        ]
        for code in cocoaCodes {
            let state = ErrorMapper.state(for: EdgeCaseFixtures.cocoaError(code))
            XCTAssertEqual(state.kind, .storageUnavailable, "\(code)")
        }

        let posixCodes = [13, 1, 30]
        for code in posixCodes {
            let state = ErrorMapper.state(
                for: NSError(domain: NSPOSIXErrorDomain, code: code)
            )
            XCTAssertEqual(state.kind, .storageUnavailable, "errno \(code)")
        }
    }

    func testUnknownWriteAndIOErrorsMapToStorageWriteFailed() {
        let cocoa = ErrorMapper.state(
            for: EdgeCaseFixtures.cocoaError(.fileWriteUnknown)
        )
        XCTAssertEqual(cocoa.kind, .storageWriteFailed)

        let posix = ErrorMapper.state(
            for: NSError(domain: NSPOSIXErrorDomain, code: 5)
        )
        XCTAssertEqual(posix.kind, .storageWriteFailed)
    }

    func testCorruptAndMissingFilesMapToPersistenceFailures() {
        for code in [CocoaError.Code.fileReadCorruptFile, .fileReadNoSuchFile] {
            let state = ErrorMapper.state(for: EdgeCaseFixtures.cocoaError(code))
            XCTAssertEqual(state.kind, .persistenceFailed)
            XCTAssertTrue(state.recoveryActions.contains(.retry))
        }
    }

    func testUnrelatedNSErrorIsNotMisclassifiedAsStorage() {
        let unrelated = NSError(domain: "ExampleDomain", code: 640)
        XCTAssertNil(ErrorMapper.storageFailureKind(for: unrelated))
        XCTAssertEqual(ErrorMapper.state(for: unrelated).kind, .unknown)

        XCTAssertNil(ErrorMapper.storageFailureKind(for: EdgeCaseOpaqueError()))
    }

    func testStorageSourceCodeNeverIncludesAFilePath() {
        let state = ErrorMapper.state(
            for: EdgeCaseFixtures.cocoaError(
                .fileWriteOutOfSpace,
                path: "/Users/alice/Photos/private-portrait.heic"
            )
        )
        let source = state.sourceCode ?? ""

        XCTAssertFalse(source.contains("Users"))
        XCTAssertFalse(source.contains("private-portrait"))
        XCTAssertFalse(source.contains(".heic"))
        XCTAssertFalse(state.diagnosticCode.rawValue.contains("Users"))
        XCTAssertFalse(state.title.text.contains("private-portrait"))
        XCTAssertFalse(state.message.text.contains("private-portrait"))
    }

    // MARK: - Headroom

    func testStorageHeadroomIsConservativeWhenSpaceIsUnknown() {
        XCTAssertEqual(
            StorageHeadroom.assess(availableBytes: nil, requiredBytes: 100),
            .unknown
        )
        XCTAssertEqual(
            StorageHeadroom.assess(availableBytes: 100, requiredBytes: 100),
            .sufficient
        )
        XCTAssertEqual(
            StorageHeadroom.assess(availableBytes: 99, requiredBytes: 100),
            .low
        )
        XCTAssertEqual(
            StorageHeadroom.assess(availableBytes: 0, requiredBytes: -50),
            .sufficient
        )
        XCTAssertEqual(
            StorageHeadroom.assess(availableBytes: 10, requiredBytes: -50),
            .sufficient
        )
    }

    func testLowStorageAdvisoryAppearsOnlyBelowTheReserve() {
        let advisor = ErrorAdvisor(lowStorageThresholdBytes: 300_000_000)

        let low = ErrorAdvisor(lowStorageThresholdBytes: 300_000_000).advisories(
            for: DeviceConditions(
                batteryLevel: 1,
                availableDiskBytes: 299_999_999
            )
        )
        XCTAssertEqual(low.map(\.kind), [.storageLow])
        XCTAssertEqual(low.first?.recoveryActions, [.freeUpSpace, .dismiss])
        XCTAssertEqual(low.first?.severity, .notice)
        XCTAssertEqual(low.first?.diagnosticCode.rawValue, "ST-STOR-001")

        let enough = advisor.advisories(
            for: DeviceConditions(
                batteryLevel: 1,
                availableDiskBytes: 300_000_000
            )
        )
        XCTAssertTrue(enough.isEmpty)

        let unknown = advisor.advisories(
            for: DeviceConditions(batteryLevel: 1, availableDiskBytes: nil)
        )
        XCTAssertTrue(unknown.isEmpty)
    }

    // MARK: - Persistence taxonomy

    func testPersistenceAndSchemaErrorsKeepTheirActions() {
        let storage = ErrorMapper.state(for: StyleToneError.persistenceFailed)
        XCTAssertEqual(storage.kind, .persistenceFailed)
        XCTAssertEqual(storage.diagnosticCode.rawValue, "ST-DATA-001")
        XCTAssertTrue(storage.recoveryActions.contains(.retry))

        let schema = ErrorMapper.state(for: StyleToneError.unsupportedSchema(version: 9))
        XCTAssertEqual(schema.kind, .schemaUnsupported)
        XCTAssertEqual(schema.diagnosticCode.rawValue, "ST-DATA-002")
        XCTAssertTrue(schema.recoveryActions.contains(.recalibrate))
    }
}
