import Foundation
import GoldenSupport
import StyleToneCore
import StyleToneUI
import TestShared
import XCTest

// MARK: - Doubles

/// Availability provider with a fixed answer.
struct StubAvailabilityProvider: PairingPickerAvailabilityProviding {
    let availability: PairingPickerAvailability

    func currentAvailability() async -> PairingPickerAvailability {
        availability
    }
}

/// Importer that fabricates a pairing photo for any payload.
struct FakeImageImporter: PairingImageImporting {
    var failure: PairingImportError? = nil
    var sourceSize = PixelSize(width: 4032, height: 3024)
    var displaySize = PixelSize(width: 800, height: 600)
    var reportedByteCount: Int? = nil

    func importImage(
        from data: Data,
        sourceIdentifier: String?,
        importedAt: Date
    ) async throws -> PairingPhoto {
        if let failure {
            throw failure
        }
        let asset = try MockImageAssetFactory.solid(size: displaySize)
        return PairingPhoto(
            asset: asset,
            sourcePixelSize: sourceSize,
            sourceIdentifier: sourceIdentifier,
            byteCount: reportedByteCount ?? data.count,
            importedAt: importedAt
        )
    }
}

/// Importer that succeeds a fixed number of times and then fails.
///
/// Used to prove that a failed replacement leaves the previous photo in place.
actor SequencedImageImporter: PairingImageImporting {
    private let successfulImports: Int
    private let displaySize: PixelSize
    private var count = 0

    init(successfulImports: Int, displaySize: PixelSize = PixelSize(width: 800, height: 600)) {
        self.successfulImports = successfulImports
        self.displaySize = displaySize
    }

    var importCount: Int { count }

    func importImage(
        from data: Data,
        sourceIdentifier: String?,
        importedAt: Date
    ) async throws -> PairingPhoto {
        count += 1
        guard count <= successfulImports else {
            throw PairingImportError.unreadableData
        }
        let asset = try MockImageAssetFactory.solid(size: displaySize)
        return PairingPhoto(
            asset: asset,
            sourcePixelSize: PixelSize(width: 4032, height: 3024),
            sourceIdentifier: sourceIdentifier,
            byteCount: data.count,
            importedAt: importedAt
        )
    }
}

/// Analyzer that always returns the same grade and records how often it ran.
actor RecordingQualityAnalyzer: PairQualityAnalyzing {
    private let quality: PairQuality
    private var calls = 0

    init(quality: PairQuality) {
        self.quality = quality
    }

    var callCount: Int { calls }

    func assess(original: ImageAsset, edited: ImageAsset) async throws -> PairQuality {
        calls += 1
        return quality
    }
}

/// Analyzer that always throws.
struct FailingQualityAnalyzer: PairQualityAnalyzing {
    var error: StyleToneError = .invalidState

    func assess(original: ImageAsset, edited: ImageAsset) async throws -> PairQuality {
        throw error
    }
}

/// Analyzer that returns a queued grade per call.
///
/// Pairs are graded in the order they are imported, which lets a test build a
/// mixed session through the real view-model flow.
actor ScriptedQualityAnalyzer: PairQualityAnalyzing {
    private let grades: [PairQualityGrade]
    private var index = 0

    init(grades: [PairQualityGrade]) {
        self.grades = grades
    }

    var callCount: Int { index }

    func assess(original: ImageAsset, edited: ImageAsset) async throws -> PairQuality {
        let grade = grades.isEmpty
            ? PairQualityGrade.good
            : grades[min(index, grades.count - 1)]
        index += 1
        return PairQuality(grade: grade, reasons: [], confidence: 0.9)
    }
}

/// Store whose load always fails with a corrupt file.
actor CorruptedSessionStore: PairingSessionStoring {
    private(set) var clearCount = 0

    func load() async throws -> PairingSessionSnapshot? {
        throw PairingSessionStoreError.corrupted
    }

    func save(_ snapshot: PairingSessionSnapshot) async throws {}

    func clear() async throws {
        clearCount += 1
    }
}

/// Store whose writes always fail.
actor FailingSaveStore: PairingSessionStoring {
    func load() async throws -> PairingSessionSnapshot? { nil }

    func save(_ snapshot: PairingSessionSnapshot) async throws {
        throw PairingSessionStoreError.writeFailed
    }

    func clear() async throws {}
}

// MARK: - Factories

enum PairingTestFactory {
    static let referenceDate = Date(timeIntervalSince1970: 1_767_225_600)

    static func quality(
        _ grade: PairQualityGrade,
        reasons: [String] = [],
        confidence: Float = 0.9
    ) -> PairQuality {
        PairQuality(grade: grade, reasons: reasons, confidence: confidence)
    }

    @MainActor
    static func viewModel(
        analyzer: any PairQualityAnalyzing = RecordingQualityAnalyzer(
            quality: PairingTestFactory.quality(.good)
        ),
        importer: any PairingImageImporting = FakeImageImporter(),
        store: any PairingSessionStoring = InMemoryPairingSessionStore(),
        clock: AdjustableTestClock = AdjustableTestClock(),
        target: PairingTarget = .three,
        availability: PairingPickerAvailability = .available
    ) -> PairingViewModel {
        PairingViewModel(
            dependencies: PairingDependencies(
                qualityAnalyzer: analyzer,
                sessionStore: store,
                imageImporter: importer,
                dateProvider: clock,
                availabilityProvider: StubAvailabilityProvider(availability: availability),
                target: target
            )
        )
    }

    /// Starts a view model with the in-memory store and the given doubles.
    @MainActor
    static func startedViewModel(
        analyzer: any PairQualityAnalyzing = RecordingQualityAnalyzer(
            quality: PairingTestFactory.quality(.good)
        ),
        importer: any PairingImageImporting = FakeImageImporter(),
        store: any PairingSessionStoring = InMemoryPairingSessionStore(),
        clock: AdjustableTestClock = AdjustableTestClock(),
        target: PairingTarget = .three,
        availability: PairingPickerAvailability = .available
    ) async -> PairingViewModel {
        let model = viewModel(
            analyzer: analyzer,
            importer: importer,
            store: store,
            clock: clock,
            target: target,
            availability: availability
        )
        await model.start()
        return model
    }

    /// Adds a pair and imports both photos, awaiting the quality check.
    @MainActor
    @discardableResult
    static func addPair(
        to viewModel: PairingViewModel,
        originalIdentifier: String? = nil,
        editedIdentifier: String? = nil
    ) async -> UUID? {
        viewModel.addPair()
        guard let request = viewModel.pendingPick else { return nil }
        let picked = [
            PairingPickedPhoto(data: Data([0x01, 0x02]), sourceIdentifier: originalIdentifier),
            PairingPickedPhoto(data: Data([0x03, 0x04]), sourceIdentifier: editedIdentifier),
        ]
        await viewModel.importPickedPhotos(picked)
        return request.pairID
    }

    /// Replaces one slot of an existing pair.
    @MainActor
    static func replace(
        _ slot: PairingSlot,
        in viewModel: PairingViewModel,
        pairID: UUID,
        identifier: String? = nil
    ) async {
        viewModel.pick(slot, in: pairID)
        guard viewModel.pendingPick != nil else { return }
        let picked = [PairingPickedPhoto(data: Data([0x05]), sourceIdentifier: identifier)]
        await viewModel.importPickedPhotos(picked)
    }

    /// Builds a session containing one graded pair per entry.
    static func session(
        grades: [PairQualityGrade?],
        target: PairingTarget,
        startedAt: Date = PairingTestFactory.referenceDate
    ) -> PairingSessionState {
        var session = PairingSessionState(target: target, startedAt: startedAt)
        for grade in grades {
            guard let pairID = session.addPair(now: startedAt) else { continue }
            guard let original = photo(seed: 1, at: startedAt),
                  let edited = photo(seed: 2, at: startedAt)
            else {
                continue
            }
            session.attach(original, to: .original, pairID: pairID, now: startedAt)
            session.attach(edited, to: .edited, pairID: pairID, now: startedAt)
            if let grade {
                let revision = session.pair(withID: pairID)?.contentRevision ?? 0
                session.completeAssessment(
                    quality(grade),
                    for: pairID,
                    revision: revision,
                    now: startedAt
                )
            }
        }
        return session
    }

    static func photo(seed: Int, at date: Date) -> PairingPhoto? {
        guard let asset = try? MockImageAssetFactory.solid(size: PixelSize(width: 64, height: 64)) else {
            return nil
        }
        return PairingPhoto(
            asset: asset,
            sourcePixelSize: PixelSize(width: 4032, height: 3024),
            sourceIdentifier: "asset-\(seed)",
            byteCount: 1_024,
            importedAt: date
        )
    }
}
