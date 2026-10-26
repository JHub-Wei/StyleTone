import Foundation
import StyleToneCore
import StyleToneUI
import TestShared
import XCTest

/// Add-only permission paths and the exits WP-19 promises when access is
/// denied, restricted or unavailable.
@MainActor
final class ExportPermissionTests: XCTestCase {
    func testNotDeterminedRequestsAddOnlyOnceAndSaves() {
        let done = expectation(description: "testNotDeterminedRequestsAddOnlyOnceAndSaves")
        Task { @MainActor in
            do {
                try await Self.run_testNotDeterminedRequestsAddOnlyOnceAndSaves()
            } catch {
                XCTFail("testNotDeterminedRequestsAddOnlyOnceAndSaves threw: \(error)")
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
    }

    @MainActor
    private static func run_testNotDeterminedRequestsAddOnlyOnceAndSaves() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportPermissionGrant")
        defer { temp.remove() }

        let exporter = FileWritingExporter(directory: temp.url)
        let library = FakePhotoLibrary(
            status: .notDetermined,
            requestResult: .authorized
        )
        let quota = FakeExportQuota(.free(remaining: 3))
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            photoLibrary: library,
            quota: quota
        )

        await model.start()
        XCTAssertEqual(model.authorization, .notDetermined)
        XCTAssertTrue(model.canSaveToLibrary)

        model.saveToLibrary()
        await model.waitForCompletion()

        XCTAssertEqual(model.stage, .finished)
        XCTAssertEqual(model.authorization, .authorized)
        let requests = await library.requestCount
        let saves = await library.saveCount
        let count = await quota.recordCount
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(count, 1)
    }

    func testDeniedPromptFailsBeforeRenderingAndOffersExits() {
        let done = expectation(description: "testDeniedPromptFailsBeforeRenderingAndOffersExits")
        Task { @MainActor in
            do {
                try await Self.run_testDeniedPromptFailsBeforeRenderingAndOffersExits()
            } catch {
                XCTFail("testDeniedPromptFailsBeforeRenderingAndOffersExits threw: \(error)")
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
    }

    @MainActor
    private static func run_testDeniedPromptFailsBeforeRenderingAndOffersExits() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportPermissionDeny")
        defer { temp.remove() }

        let renderer = ScriptedRenderer()
        let exporter = FileWritingExporter(directory: temp.url)
        let library = FakePhotoLibrary(
            status: .notDetermined,
            requestResult: .denied
        )
        let quota = FakeExportQuota(.free(remaining: 3))
        let model = try ExportTestFactory.model(
            directory: temp.url,
            renderer: renderer,
            exporter: exporter,
            photoLibrary: library,
            quota: quota
        )

        await model.start()
        model.saveToLibrary()
        await model.waitForCompletion()

        XCTAssertEqual(model.stage, .failed)
        XCTAssertEqual(model.failure?.kind, .permissionDenied)
        XCTAssertEqual(model.authorization, .denied)

        let recoveries = try XCTUnwrap(model.failure?.recoveries)
        XCTAssertTrue(recoveries.contains(.openSettings))
        XCTAssertTrue(recoveries.contains(.shareInstead))
        XCTAssertTrue(recoveries.contains(.retry))
        XCTAssertTrue(recoveries.contains(.dismiss))

        let renderCalls = await renderer.callCount
        let saveCalls = await library.saveCount
        let count = await quota.recordCount
        XCTAssertEqual(renderCalls, 0)
        XCTAssertEqual(saveCalls, 0)
        XCTAssertEqual(count, 0)

        let files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertTrue(files.isEmpty)

        model.shareInstead()
        await model.waitForCompletion()
        XCTAssertEqual(model.stage, .awaitingShare)
        let request = try XCTUnwrap(model.pendingShare)
        await model.completeShare(request, completed: true)

        XCTAssertEqual(model.stage, .finished)
        let counted = await quota.recordCount
        XCTAssertEqual(counted, 1)
        let remaining = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testRestrictedLibraryOffersOnlyShareAndDismiss() {
        let done = expectation(description: "testRestrictedLibraryOffersOnlyShareAndDismiss")
        Task { @MainActor in
            do {
                try await Self.run_testRestrictedLibraryOffersOnlyShareAndDismiss()
            } catch {
                XCTFail("testRestrictedLibraryOffersOnlyShareAndDismiss threw: \(error)")
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
    }

    @MainActor
    private static func run_testRestrictedLibraryOffersOnlyShareAndDismiss() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportPermissionRestricted")
        defer { temp.remove() }

        let renderer = ScriptedRenderer()
        let exporter = FileWritingExporter(directory: temp.url)
        let library = FakePhotoLibrary(status: .restricted)
        let model = try ExportTestFactory.model(
            directory: temp.url,
            renderer: renderer,
            exporter: exporter,
            photoLibrary: library
        )

        await model.start()
        XCTAssertFalse(model.canSaveToLibrary)

        model.saveToLibrary()
        await model.waitForCompletion()

        XCTAssertEqual(model.failure?.kind, .permissionRestricted)
        let restrictedRecoveries = try XCTUnwrap(model.failure?.recoveries)
        XCTAssertEqual(restrictedRecoveries, [.shareInstead, .dismiss])
        let renderCalls = await renderer.callCount
        XCTAssertEqual(renderCalls, 0)

        model.shareInstead()
        await model.waitForCompletion()
        XCTAssertEqual(model.stage, .awaitingShare)
    }

    func testUnavailableLibraryOffersShareExit() {
        let done = expectation(description: "testUnavailableLibraryOffersShareExit")
        Task { @MainActor in
            do {
                try await Self.run_testUnavailableLibraryOffersShareExit()
            } catch {
                XCTFail("testUnavailableLibraryOffersShareExit threw: \(error)")
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
    }

    @MainActor
    private static func run_testUnavailableLibraryOffersShareExit() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportPermissionUnavailable")
        defer { temp.remove() }

        let renderer = ScriptedRenderer()
        let exporter = FileWritingExporter(directory: temp.url)
        let library = FakePhotoLibrary(status: .unavailable)
        let quota = FakeExportQuota(.free(remaining: 3))
        let model = try ExportTestFactory.model(
            directory: temp.url,
            renderer: renderer,
            exporter: exporter,
            photoLibrary: library,
            quota: quota
        )

        await model.start()
        XCTAssertFalse(model.canSaveToLibrary)

        model.saveToLibrary()
        await model.waitForCompletion()

        XCTAssertEqual(model.failure?.kind, .photoLibraryUnavailable)
        let unavailableRecoveries = try XCTUnwrap(model.failure?.recoveries)
        XCTAssertEqual(unavailableRecoveries, [.shareInstead, .dismiss])
        let renderCalls = await renderer.callCount
        XCTAssertEqual(renderCalls, 0)

        model.shareInstead()
        await model.waitForCompletion()
        let request = try XCTUnwrap(model.pendingShare)
        await model.completeShare(request, completed: true)

        XCTAssertEqual(model.stage, .finished)
        let count = await quota.recordCount
        XCTAssertEqual(count, 1)
    }

    func testDeniedAtStartSucceedsAfterSettingsAreOpenedAndRetried() {
        let done = expectation(description: "testDeniedAtStartSucceedsAfterSettingsAreOpenedAndRetried")
        Task { @MainActor in
            do {
                try await Self.run_testDeniedAtStartSucceedsAfterSettingsAreOpenedAndRetried()
            } catch {
                XCTFail("testDeniedAtStartSucceedsAfterSettingsAreOpenedAndRetried threw: \(error)")
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
    }

    @MainActor
    private static func run_testDeniedAtStartSucceedsAfterSettingsAreOpenedAndRetried() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportPermissionSettings")
        defer { temp.remove() }

        let exporter = FileWritingExporter(directory: temp.url)
        let library = FakePhotoLibrary(status: .denied)
        let quota = FakeExportQuota(.free(remaining: 3))
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            photoLibrary: library,
            quota: quota
        )

        await model.start()
        XCTAssertFalse(model.canSaveToLibrary)

        model.saveToLibrary()
        await model.waitForCompletion()
        XCTAssertEqual(model.failure?.kind, .permissionDenied)

        await library.setStatus(.authorized)
        await model.refreshAuthorization()
        XCTAssertTrue(model.canSaveToLibrary)

        model.retry()
        await model.waitForCompletion()

        XCTAssertEqual(model.stage, .finished)
        XCTAssertNil(model.failure)
        let count = await quota.recordCount
        XCTAssertEqual(count, 1)
    }

    func testPhotoKitSaveRejectionKeepsFileAndRetriesWithoutReencoding() {
        let done = expectation(description: "testPhotoKitSaveRejectionKeepsFileAndRetriesWithoutReencoding")
        Task { @MainActor in
            do {
                try await Self.run_testPhotoKitSaveRejectionKeepsFileAndRetriesWithoutReencoding()
            } catch {
                XCTFail("testPhotoKitSaveRejectionKeepsFileAndRetriesWithoutReencoding threw: \(error)")
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
    }

    @MainActor
    private static func run_testPhotoKitSaveRejectionKeepsFileAndRetriesWithoutReencoding() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportPermissionSaveRetry")
        defer { temp.remove() }

        let exporter = FileWritingExporter(directory: temp.url)
        let library = FakePhotoLibrary(saveError: .permissionDenied)
        let quota = FakeExportQuota(.free(remaining: 3))
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            photoLibrary: library,
            quota: quota
        )

        await model.start()
        model.saveToLibrary()
        await model.waitForCompletion()

        XCTAssertEqual(model.failure?.kind, .permissionDenied)
        XCTAssertEqual(model.failure?.stage, .savingToLibrary)
        XCTAssertTrue(model.failure?.keepsStagedFile ?? false)
        var files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertEqual(files.count, 1)

        await library.setSaveError(nil)
        model.retry()
        await model.waitForCompletion()

        XCTAssertEqual(model.stage, .finished)
        let exportCalls = exporter.callCount
        let saves = await library.saveCount
        let count = await quota.recordCount
        XCTAssertEqual(exportCalls, 1, "retry should save the staged file, not re-encode")
        XCTAssertEqual(saves, 2)
        XCTAssertEqual(count, 1)
        files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertTrue(files.isEmpty)
    }

    func testCanShareEvenWhenLibraryAccessIsDenied() {
        let done = expectation(description: "testCanShareEvenWhenLibraryAccessIsDenied")
        Task { @MainActor in
            do {
                try await Self.run_testCanShareEvenWhenLibraryAccessIsDenied()
            } catch {
                XCTFail("testCanShareEvenWhenLibraryAccessIsDenied threw: \(error)")
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
    }

    @MainActor
    private static func run_testCanShareEvenWhenLibraryAccessIsDenied() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportPermissionShare")
        defer { temp.remove() }

        let exporter = FileWritingExporter(directory: temp.url)
        let library = FakePhotoLibrary(status: .denied)
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            photoLibrary: library,
            supportsShare: true
        )

        await model.start()
        XCTAssertTrue(model.canShare)
        XCTAssertFalse(model.canSaveToLibrary)
    }
}
