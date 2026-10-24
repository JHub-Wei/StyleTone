#if DEBUG
import CoreGraphics
import StyleToneCore
import SwiftUI

/// Deterministic preview fixtures for the pairing screen.
///
/// Images are synthetic gradients from the design-system preview data; no
/// photograph from a library or fixture directory is used.
@MainActor
enum PairingPreviewData {
    /// 2026-01-01T00:00:00Z, the project reference date.
    static let referenceDate = Date(timeIntervalSince1970: 1_767_225_600)

    static func photo(seed: Int) -> PairingPhoto? {
        guard let asset = DesignSystemPreviewData.sampleImage() else {
            return nil
        }
        return PairingPhoto(
            asset: asset,
            sourcePixelSize: PixelSize(width: 4032, height: 3024),
            sourceIdentifier: "preview-\(seed)",
            byteCount: 2_400_000,
            importedAt: referenceDate
        )
    }

    static func reasons(for grade: PairQualityGrade) -> [String] {
        switch grade {
        case .good:
            return []
        case .warning:
            return [PairingQualityReasonKeys.structureChanged]
        case .rejected:
            return [
                PairingQualityReasonKeys.semanticMismatch,
                PairingQualityReasonKeys.notRegistered,
            ]
        }
    }

    /// Builds a session with one complete pair per grade.
    static func session(
        grades: [PairQualityGrade?],
        target: PairingTarget
    ) -> PairingSessionState {
        var session = PairingSessionState(target: target, startedAt: referenceDate)

        for (index, grade) in grades.enumerated() {
            guard let pairID = session.addPair(now: referenceDate) else { continue }

            if let original = photo(seed: index * 2),
               let edited = photo(seed: index * 2 + 1) {
                session.attach(original, to: .original, pairID: pairID, now: referenceDate)
                session.attach(edited, to: .edited, pairID: pairID, now: referenceDate)
            }

            if let grade {
                let quality = PairQuality(
                    grade: grade,
                    reasons: reasons(for: grade),
                    confidence: 0.9
                )
                let revision = session.pair(withID: pairID)?.contentRevision ?? 0
                session.completeAssessment(
                    quality,
                    for: pairID,
                    revision: revision,
                    now: referenceDate
                )
            }
        }

        return session
    }

    static func viewModel(
        grades: [PairQualityGrade?],
        target: PairingTarget = .five
    ) -> PairingViewModel {
        let viewModel = PairingViewModel(
            dependencies: PairingDependencies(target: target)
        )
        viewModel.seedForPreview(session(grades: grades, target: target))
        return viewModel
    }

    static let empty: PairingViewModel = {
        let viewModel = PairingViewModel(dependencies: PairingDependencies())
        viewModel.seedForPreview(
            PairingSessionState(target: .three, startedAt: referenceDate)
        )
        return viewModel
    }()

    static let populated: PairingViewModel = viewModel(
        grades: [.good, .warning, .rejected, nil],
        target: .five
    )
}

@MainActor
private struct PairingScreenPreview: View {
    let viewModel: PairingViewModel

    var body: some View {
        NavigationStack {
            PairingScreen(
                viewModel: viewModel,
                onFinish: { _, _ in },
                onSkip: { _ in }
            )
        }
        .styleToneTheme(.dark)
        .preferredColorScheme(.dark)
    }
}

#Preview("Pairing / empty") {
    PairingScreenPreview(viewModel: PairingPreviewData.empty)
}

#Preview("Pairing / grades") {
    PairingScreenPreview(viewModel: PairingPreviewData.populated)
}

#Preview("Pairing / large type") {
    PairingScreenPreview(viewModel: PairingPreviewData.populated)
        .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("Pairing / light") {
    NavigationStack {
        PairingScreen(
            viewModel: PairingPreviewData.populated,
            onFinish: { _, _ in },
            onSkip: { _ in }
        )
    }
    .styleToneTheme(.light)
    .preferredColorScheme(.light)
}

#Preview("Pairing / increased contrast") {
    NavigationStack {
        PairingScreen(
            viewModel: PairingPreviewData.populated,
            onFinish: { _, _ in },
            onSkip: { _ in }
        )
    }
    .styleToneTheme(.darkHighContrast)
    .preferredColorScheme(.dark)
}
#endif
