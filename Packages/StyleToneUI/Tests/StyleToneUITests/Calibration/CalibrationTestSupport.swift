import Foundation
import StyleToneCore
import TestShared

enum CalibrationTestSupport {
    static func pairs(
        _ count: Int,
        warningsAt: Set<Int> = [],
        rejectedAt: Set<Int> = []
    ) throws -> [PairSample] {
        let image = try MockImageAssetFactory.solid()
        return (0..<count).map { index in
            let grade: PairQualityGrade
            if rejectedAt.contains(index) {
                grade = .rejected
            } else if warningsAt.contains(index) {
                grade = .warning
            } else {
                grade = .good
            }
            return PairSample(
                original: image,
                edited: image,
                quality: PairQuality(grade: grade, confidence: 0.9)
            )
        }
    }
}
