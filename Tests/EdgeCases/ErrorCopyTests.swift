import StyleToneUI
import XCTest

/// Copy and key invariants for every error surface.
final class ErrorCopyTests: XCTestCase {
    func testAllTextsUseValidErrorKeys() {
        for text in ErrorCopy.allTexts {
            XCTAssertEqual(text.key.prefix, LocalizationPrefix.error, "key \(text.key.rawValue)")
            XCTAssertTrue(text.key.isValid, "key \(text.key.rawValue)")
            XCTAssertFalse(text.fallback.isEmpty, "fallback for \(text.key.rawValue)")
        }
    }

    func testEveryKindHasATitleAndMessage() {
        for kind in ErrorKind.allCases {
            let title = ErrorCopy.title(kind)
            let message = ErrorCopy.message(kind)
            XCTAssertFalse(title.fallback.isEmpty, "title \(kind)")
            XCTAssertFalse(message.fallback.isEmpty, "message \(kind)")
            XCTAssertEqual(title.key.prefix, LocalizationPrefix.error)
            XCTAssertEqual(message.key.prefix, LocalizationPrefix.error)
            XCTAssertFalse(title.text.isEmpty)
            XCTAssertFalse(message.text.isEmpty)
        }
    }

    func testEveryActionHasCopy() {
        for action in RecoveryAction.allCases {
            let title = ErrorCopy.actionTitle(action)
            XCTAssertFalse(title.fallback.isEmpty, "action \(action)")
            XCTAssertEqual(title.key.prefix, LocalizationPrefix.error)
            XCTAssertTrue(title.key.isValid)
            XCTAssertFalse(title.text.isEmpty)
        }
    }

    func testFallbacksAreAsciiEnglishWithoutPII() {
        for text in ErrorCopy.allTexts {
            XCTAssertTrue(
                text.fallback.utf8.allSatisfy { $0 < 128 },
                "non-ASCII fallback \(text.key.rawValue): \(text.fallback)"
            )
            XCTAssertFalse(
                EdgeCaseFixtures.containsPathLikeText(text.fallback),
                "path-like copy \(text.key.rawValue): \(text.fallback)"
            )
            XCTAssertFalse(
                text.fallback.contains("http://") || text.fallback.contains("https://"),
                "URL copy \(text.key.rawValue)"
            )
            XCTAssertFalse(text.fallback.contains("private-portrait"))
            XCTAssertFalse(text.fallback.contains("alice"))
        }
    }

    func testDiagnosticFormatCarriesTheCode() {
        let rendered = ErrorCopy.diagnosticText("ST-NET-001")
        XCTAssertTrue(rendered.contains("ST-NET-001"))
        XCTAssertTrue(rendered.contains("Support code:"))
        XCTAssertTrue(ErrorCopy.diagnosticFormat.fallback.contains("%@"))
        XCTAssertTrue(ErrorCopy.diagnosticFormat.key.isValid)
    }

    func testAllTextsCoversTheWholeCatalog() {
        let expected = ErrorKind.allCases.count * 2
            + RecoveryAction.allCases.count
            + 1
        XCTAssertEqual(ErrorCopy.allTexts.count, expected)
    }

    func testEveryVisibleKindHasAPrimaryAction() {
        XCTAssertTrue(RecoveryAction.allCases.contains { $0.isPreferred })
        for kind in ErrorKind.allCases {
            if kind.isSilent {
                XCTAssertNil(ErrorState(kind: kind).primaryAction)
            } else {
                XCTAssertNotNil(
                    ErrorState(kind: kind).primaryAction,
                    "no primary action for \(kind)"
                )
            }
        }
    }

    func testPIIDetectorUsedByTheAudits() {
        // The helper is shared with the source audit; keep its detector honest.
        XCTAssertTrue(EdgeCaseFixtures.containsPathLikeText("/Users/alice/x.jpg"))
        XCTAssertFalse(EdgeCaseFixtures.containsPathLikeText("Try again"))
        XCTAssertFalse(EdgeCaseFixtures.containsPathLikeText("Support code: ST-NET-001"))
    }
}
