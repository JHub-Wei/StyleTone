import StyleToneUI
import XCTest

/// Interruption edges: an incoming call pauses one job, resume is idempotent,
/// and a user cancellation never masquerades as an interruption.
@MainActor
final class InterruptionTests: XCTestCase {
    func testIncomingCallInterruptsRunningJob() {
        let coordinator = InterruptionCoordinator(context: .export)
        let jobID = coordinator.beginJob()

        let state = coordinator.interrupt(.incomingCall)

        XCTAssertNotNil(state)
        XCTAssertEqual(state?.kind, .interrupted)
        XCTAssertEqual(state?.context, .export)
        XCTAssertEqual(state?.severity, .notice)
        XCTAssertEqual(state?.diagnosticCode.rawValue, "ST-SYS-003")
        XCTAssertEqual(state?.recoveryActions, [.resume, .dismiss])
        XCTAssertEqual(state?.sourceCode, "INTERRUPTION_INCOMINGCALL")
        XCTAssertEqual(coordinator.phase, .interrupted(jobID, .incomingCall))
        XCTAssertEqual(coordinator.activeJobID, jobID)
        XCTAssertTrue(coordinator.isInterrupted)
        XCTAssertEqual(coordinator.interruptionCount, 1)
        XCTAssertEqual(coordinator.lastInterruption?.reason, .incomingCall)
        XCTAssertEqual(coordinator.lastInterruption?.jobID, jobID)
    }

    func testResumeHappensExactlyOnce() {
        let coordinator = InterruptionCoordinator()
        let jobID = coordinator.beginJob()
        _ = coordinator.interrupt(.background)

        XCTAssertTrue(coordinator.resume())
        XCTAssertEqual(coordinator.phase, .running(jobID))
        XCTAssertEqual(coordinator.resumeCount, 1)
        XCTAssertFalse(coordinator.isInterrupted)
        XCTAssertTrue(coordinator.isRunning)

        XCTAssertFalse(coordinator.resume())
        XCTAssertEqual(coordinator.resumeCount, 1)
        XCTAssertEqual(coordinator.phase, .running(jobID))
    }

    func testInterruptOutsideAJobDoesNothing() {
        let coordinator = InterruptionCoordinator()

        XCTAssertNil(coordinator.interrupt(.incomingCall))
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(coordinator.interruptionCount, 0)
        XCTAssertNil(coordinator.lastInterruption)

        coordinator.complete()
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertNil(coordinator.interrupt(.systemAlert))
    }

    func testSecondInterruptionKeepsTheFirstReason() {
        let coordinator = InterruptionCoordinator()
        _ = coordinator.beginJob()

        let first = coordinator.interrupt(.incomingCall)
        let second = coordinator.interrupt(.siri)

        XCTAssertNotNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(coordinator.interruptionCount, 1)
        XCTAssertEqual(coordinator.lastInterruption?.reason, .incomingCall)
        XCTAssertTrue(coordinator.isInterrupted)
    }

    func testCompletingWhileInterruptedStopsFurtherInterruptions() {
        let coordinator = InterruptionCoordinator()
        _ = coordinator.beginJob()
        _ = coordinator.interrupt(.systemAlert)

        coordinator.complete()
        if case .completed(_) = coordinator.phase {
            // expected
        } else {
            XCTFail("expected a completed phase")
        }
        XCTAssertNil(coordinator.activeJobID)
        XCTAssertNil(coordinator.interrupt(.background))
        XCTAssertFalse(coordinator.resume())
        XCTAssertEqual(coordinator.resumeCount, 0)
    }

    func testUserCancellationIsNotAnInterruption() {
        let coordinator = InterruptionCoordinator()
        _ = coordinator.beginJob()

        coordinator.reset()

        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(coordinator.interruptionCount, 0)
        XCTAssertNil(coordinator.lastInterruption)
        XCTAssertNil(coordinator.interrupt(.incomingCall))
        XCTAssertFalse(coordinator.resume())
    }

    func testEveryInterruptionReasonUsesAPathFreeSourceCode() {
        for reason in InterruptionReason.allCases {
            let coordinator = InterruptionCoordinator(context: .editor)
            _ = coordinator.beginJob()
            let state = coordinator.interrupt(reason)

            let source = state?.sourceCode ?? ""
            XCTAssertTrue(
                source.hasPrefix("INTERRUPTION_"),
                "source for \(reason): \(source)"
            )
            XCTAssertFalse(source.contains("/"))
            XCTAssertFalse(source.contains("alice"))
            XCTAssertFalse(state?.title.text.contains("/") ?? true)
            XCTAssertEqual(state?.recoveryActions.first, .resume)
        }
    }

    func testRepeatedInterruptionCyclesStayConsistent() {
        let coordinator = InterruptionCoordinator()

        for _ in 0..<200 {
            let jobID = coordinator.beginJob()
            XCTAssertNotNil(coordinator.interrupt(.incomingCall))
            XCTAssertTrue(coordinator.resume())
            XCTAssertEqual(coordinator.phase, .running(jobID))
            coordinator.complete()
            XCTAssertNil(coordinator.activeJobID)
        }

        XCTAssertEqual(coordinator.interruptionCount, 200)
        XCTAssertEqual(coordinator.resumeCount, 200)
        // The last interruption is retained for diagnostics; the next beginJob
        // clears it, and the counters stay cumulative.
        XCTAssertEqual(coordinator.lastInterruption?.reason, .incomingCall)
    }

    func testPresenterCanResumeAndDismissTheInterruptionCard() {
        let logger = EdgeCaseRecordingLogger()
        let presenter = ErrorPresenter(
            logger: logger,
            dateProvider: EdgeCaseDateProvider()
        )
        let coordinator = InterruptionCoordinator(context: .editor)
        let spy = EdgeCaseRecoverySpy()
        presenter.onRecovery = spy.record

        _ = coordinator.beginJob()
        guard let state = coordinator.interrupt(.incomingCall) else {
            return XCTFail("expected an interruption state")
        }
        presenter.present(state)

        XCTAssertEqual(presenter.current, state)
        XCTAssertTrue(presenter.perform(.resume))
        XCTAssertEqual(spy.count, 1)
        XCTAssertEqual(spy.received.first?.0, .resume)
        XCTAssertTrue(coordinator.resume())
        XCTAssertEqual(coordinator.resumeCount, 1)

        XCTAssertTrue(presenter.perform(.dismiss))
        XCTAssertNil(presenter.current)
        XCTAssertEqual(spy.count, 1)
        XCTAssertTrue(
            logger.entries.contains { entry in
                entry.metadata["action"] == RecoveryAction.resume.rawValue
            }
        )
    }
}
