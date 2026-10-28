import StyleToneCore
import StyleToneUI
import XCTest

/// Presenter behaviour: one visible card, bounded path-free history, recovery
/// dispatch and no trap under repeated presentations.
@MainActor
final class ErrorPresenterTests: XCTestCase {
    private func makePresenter(
        maximumHistory: Int = 20,
        logger: EdgeCaseRecordingLogger = EdgeCaseRecordingLogger()
    ) -> ErrorPresenter {
        ErrorPresenter(
            logger: logger,
            dateProvider: EdgeCaseDateProvider(),
            maximumHistory: maximumHistory
        )
    }

    func testPresentSetsCurrentAndHistory() {
        let presenter = makePresenter()
        let state = ErrorState(kind: .renderFailed, context: .editor)

        presenter.present(state)

        XCTAssertEqual(presenter.current, state)
        XCTAssertEqual(presenter.history.count, 1)
        XCTAssertEqual(presenter.history.first?.diagnosticCode, state.diagnosticCode)
        XCTAssertEqual(presenter.history.first?.sourceCode, state.sourceCode)
        XCTAssertEqual(presenter.history.first?.kind, .renderFailed)
        XCTAssertEqual(presenter.history.first?.context, .editor)
        XCTAssertEqual(presenter.history.first?.severity, .recoverable)
        XCTAssertEqual(presenter.history.first?.occurredAt, EdgeCaseDateProvider.reference)
    }

    func testPresentingAStateClearsAnOldToast() {
        let presenter = makePresenter()
        presenter.presentAsToast(ErrorState(kind: .lowBattery))
        XCTAssertNotNil(presenter.toast)

        presenter.present(ErrorState(kind: .storageFull))
        XCTAssertNil(presenter.toast)
        XCTAssertEqual(presenter.current?.kind, .storageFull)
    }

    func testSilentCancellationIsNotSurfaced() {
        let logger = EdgeCaseRecordingLogger()
        let presenter = makePresenter(logger: logger)

        presenter.present(StyleToneError.cancelled)

        XCTAssertNil(presenter.current)
        XCTAssertNil(presenter.toast)
        XCTAssertTrue(presenter.history.isEmpty)
        XCTAssertEqual(logger.entries.count, 1)
        XCTAssertEqual(logger.entries.first?.level, .info)
        XCTAssertEqual(logger.entries.first?.message, "ui.error.suppressed")
        XCTAssertEqual(
            logger.entries.first?.metadata["code"],
            ErrorKind.cancelled.diagnosticCode.rawValue
        )
    }

    func testPresentMapsAnyError() {
        let presenter = makePresenter()

        presenter.present(EdgeCasePIIError(), context: .settings)

        XCTAssertEqual(presenter.current?.kind, .unknown)
        XCTAssertEqual(presenter.current?.context, .settings)
        XCTAssertEqual(presenter.current?.diagnosticCode.rawValue, "ST-UNKNOWN-001")
        XCTAssertFalse(
            presenter.current?.sourceCode?.contains("private-portrait") ?? true
        )
    }

    func testDismissClearsCurrent() {
        let presenter = makePresenter()
        presenter.present(ErrorState(kind: .offline))
        XCTAssertNotNil(presenter.current)

        presenter.dismiss()
        XCTAssertNil(presenter.current)
        XCTAssertEqual(presenter.history.count, 1)
    }

    func testRecoveryHandlerIsCalledOncePerPerform() {
        let presenter = makePresenter()
        let state = ErrorState(kind: .renderFailed, context: .editor)
        let spy = EdgeCaseRecoverySpy()
        presenter.onRecovery = spy.record
        presenter.present(state)

        XCTAssertTrue(presenter.perform(.retry))
        XCTAssertEqual(spy.count, 1)
        XCTAssertEqual(spy.received.first?.0, .retry)
        XCTAssertEqual(spy.received.first?.1, state)
        XCTAssertEqual(presenter.current, state)

        XCTAssertFalse(presenter.perform(.resume))
        XCTAssertEqual(spy.count, 1)
    }

    func testDismissWorksWithoutAHandler() {
        let presenter = makePresenter()
        presenter.present(ErrorState(kind: .offline))

        XCTAssertTrue(presenter.perform(.dismiss))
        XCTAssertNil(presenter.current)
    }

    func testNonDismissActionWithoutHandlerLeavesTheCardVisible() {
        let presenter = makePresenter()
        presenter.present(ErrorState(kind: .offline))

        XCTAssertFalse(presenter.perform(.retry))
        XCTAssertNotNil(presenter.current)
    }

    func testPerformRejectsAnActionTheStateDoesNotOffer() {
        let presenter = makePresenter()
        presenter.present(ErrorState(kind: .storageLow))

        XCTAssertTrue(presenter.canPerform(.freeUpSpace))
        XCTAssertFalse(presenter.canPerform(.restorePurchase))
        XCTAssertFalse(presenter.perform(.restorePurchase))
    }

    func testPresentOnceDeduplicatesByCodeAndCanBeReset() {
        let presenter = makePresenter()
        let advisory = ErrorState(kind: .lowBattery)

        presenter.presentOnce(advisory)
        presenter.presentOnce(advisory)
        XCTAssertEqual(presenter.history.count, 1)

        presenter.resetSuppression()
        presenter.presentOnce(advisory)
        XCTAssertEqual(presenter.history.count, 2)
    }

    func testToastPresentationAndDismissal() {
        let presenter = makePresenter()
        let state = ErrorState(kind: .lowBattery)

        presenter.presentAsToast(state, duration: 0)

        let toast = presenter.toast
        XCTAssertNotNil(toast)
        XCTAssertNil(presenter.current)
        XCTAssertEqual(toast?.kind, .warning)
        XCTAssertEqual(toast?.duration, 0)
        XCTAssertEqual(toast?.text, state.message.text)
        XCTAssertEqual(presenter.history.count, 1)

        presenter.dismissToast(id: UUID())
        XCTAssertNotNil(presenter.toast)
        if let id = toast?.id {
            presenter.dismissToast(id: id)
        }
        XCTAssertNil(presenter.toast)
    }

    func testToastMessageFollowsSeverity() {
        let warning = ErrorState(kind: .lowBattery).toastMessage()
        let error = ErrorState(kind: .storageFull).toastMessage()
        XCTAssertEqual(warning.kind, .warning)
        XCTAssertEqual(error.kind, .error)
        XCTAssertEqual(warning.text, ErrorKind.lowBattery.messageText)
        XCTAssertEqual(error.text, ErrorKind.storageFull.messageText)
    }

    func testHistoryIsBounded() {
        let presenter = makePresenter(maximumHistory: 3)
        for kind in [ErrorKind.offline, .storageFull, .renderFailed, .noFace, .unknown] {
            presenter.present(ErrorState(kind: kind))
        }

        XCTAssertEqual(presenter.history.count, 3)
        XCTAssertEqual(
            presenter.history.map(\.kind),
            [.renderFailed, .noFace, .unknown]
        )
        XCTAssertEqual(presenter.current?.kind, .unknown)
    }

    func testLoggerReceivesCodesAndNoUserText() {
        let logger = EdgeCaseRecordingLogger()
        let presenter = makePresenter(logger: logger)

        presenter.present(EdgeCasePIIError(), context: .settings)

        XCTAssertEqual(logger.entries.count, 1)
        guard let entry = logger.entries.first else {
            return XCTFail("expected a presented-error log entry")
        }
        XCTAssertEqual(entry.message, "ui.error.presented")
        XCTAssertEqual(entry.level, .error)
        XCTAssertEqual(entry.metadata["code"], "ST-UNKNOWN-001")
        XCTAssertEqual(entry.metadata["context"], ErrorContext.settings.rawValue)
        XCTAssertEqual(entry.metadata["domain"], ErrorDomain.unknown.rawValue)
        XCTAssertFalse(entry.metadata.keys.contains("message"))
        XCTAssertFalse(entry.metadata.keys.contains("text"))
        for value in entry.metadata.values {
            XCTAssertFalse(value.contains("/"))
            XCTAssertFalse(value.contains(".jpg"))
            XCTAssertFalse(value.contains("private-portrait"))
            XCTAssertFalse(value.contains("@"))
        }
    }

    func testRecoveryIsLoggedWithTheActionButNoUserText() {
        let logger = EdgeCaseRecordingLogger()
        let presenter = makePresenter(logger: logger)
        presenter.onRecovery = { _, _ in }
        presenter.present(ErrorState(kind: .renderFailed))

        XCTAssertTrue(presenter.perform(.retry))

        guard let entry = logger.entries.last else {
            return XCTFail("expected a recovery log entry")
        }
        XCTAssertEqual(entry.message, "ui.error.recovery")
        XCTAssertEqual(entry.metadata["action"], RecoveryAction.retry.rawValue)
        XCTAssertEqual(entry.metadata["code"], "ST-RND-001")
        XCTAssertFalse(entry.metadata.keys.contains("message"))
    }

    func testRecoveryHandlerCanPresentANewStateWithoutRecursing() {
        let presenter = makePresenter()
        let counter = EdgeCaseCounter()
        presenter.onRecovery = { _, _ in
            counter.increment()
            presenter.present(ErrorState(kind: .storageFull))
        }
        presenter.present(ErrorState(kind: .renderFailed))

        XCTAssertTrue(presenter.perform(.retry))
        XCTAssertEqual(counter.value, 1)
        XCTAssertEqual(presenter.current?.kind, .storageFull)
    }

    func testRapidPresentationDoesNotCrashOrGrowHistory() {
        let presenter = makePresenter(maximumHistory: 5)
        let kinds: [ErrorKind] = [.offline, .storageFull, .renderFailed, .noFace]

        for index in 0..<500 {
            presenter.present(ErrorState(kind: kinds[index % kinds.count]))
        }

        XCTAssertEqual(presenter.history.count, 5)
        XCTAssertEqual(presenter.current?.kind, kinds[(500 - 1) % kinds.count])
    }
}

private extension ErrorKind {
    var messageText: String {
        ErrorCopy.message(self).text
    }
}
