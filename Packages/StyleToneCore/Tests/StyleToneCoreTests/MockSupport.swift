import CoreFoundation
import CoreGraphics
import Foundation
import StyleToneCore

enum TestImageFactory {
    static func make(width: Int = 4, height: Int = 3) throws -> ImageAsset {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            bytes[index] = 255
            bytes[index + 1] = 128
            bytes[index + 2] = 64
            bytes[index + 3] = 255
        }

        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else {
            throw TestError.imageCreation
        }
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw TestError.imageCreation
        }

        return ImageAsset(cgImage: image, colorSpace: colorSpace)
    }
}

enum TestError: Error {
    case imageCreation
}

struct MockPortraitAnalyzer: PortraitAnalyzing {
    let result: Result<PortraitAnalysis, StyleToneError>

    init(result: Result<PortraitAnalysis, StyleToneError>) {
        self.result = result
    }

    func analyze(_ image: ImageAsset) async throws -> PortraitAnalysis {
        try result.get()
    }
}

struct MockPairQualityAnalyzer: PairQualityAnalyzing {
    let quality: PairQuality

    func assess(original: ImageAsset, edited: ImageAsset) async throws -> PairQuality {
        quality
    }
}

struct MockStyleLearner: StyleLearning {
    let profile: StyleProfile

    func learn(samples: [PairSample], answers: [CalibrationAnswer]) async throws -> StyleProfile {
        profile
    }
}

actor MockPurchaser: PurchaseServicing {
    private var currentState: PurchaseState
    private let productValue: PurchaseProduct

    init(
        state: PurchaseState = .unknown,
        product: PurchaseProduct = PurchaseProduct(
            id: "com.styletone.pro.monthly",
            displayPrice: "¥29.9",
            period: "month"
        )
    ) {
        self.currentState = state
        self.productValue = product
    }

    var state: PurchaseState { currentState }

    func product() async throws -> PurchaseProduct {
        productValue
    }

    func purchase() async throws -> PurchaseState {
        currentState = .active
        return currentState
    }

    func restore() async throws -> PurchaseState {
        currentState
    }
}

actor MockStyleProfileStore: StyleProfileStore {
    private var profile: StyleProfile?

    init(profile: StyleProfile? = nil) {
        self.profile = profile
    }

    func loadActive() async throws -> StyleProfile? {
        profile
    }

    func save(_ profile: StyleProfile) async throws {
        self.profile = profile
    }

    func deleteAll() async throws {
        profile = nil
    }
}
