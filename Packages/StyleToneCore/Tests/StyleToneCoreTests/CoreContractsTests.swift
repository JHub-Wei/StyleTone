import XCTest
import StyleToneCore

final class CoreContractsTests: XCTestCase {
    func testMaskBufferValidation() throws {
        let mask = try MaskBuffer(width: 2, height: 2, bytes: Data([0, 64, 128, 255]))
        XCTAssertEqual(mask.pixelCount, 4)
        XCTAssertEqual(mask.value(x: 1, y: 1), 255)
        XCTAssertNil(mask.value(x: 2, y: 0))
        let normalized = try XCTUnwrap(mask.normalizedValue(x: 0, y: 1))
        XCTAssertEqual(normalized, 128.0 / 255.0, accuracy: 0.0001)

        XCTAssertThrowsError(try MaskBuffer(width: 0, height: 2, bytes: Data())) { error in
            XCTAssertEqual(error as? MaskBufferError, .invalidDimensions(width: 0, height: 2))
        }
        XCTAssertThrowsError(try MaskBuffer(width: 2, height: 2, bytes: Data([0, 1]))) { error in
            XCTAssertEqual(error as? MaskBufferError, .byteCountMismatch(expected: 4, actual: 2))
        }
    }

    func testImageAssetDimensions() throws {
        let image = try TestImageFactory.make(width: 7, height: 5)
        XCTAssertEqual(image.pixelSize, PixelSize(width: 7, height: 5))
        XCTAssertEqual(image.width, 7)
        XCTAssertEqual(image.height, 5)
        XCTAssertTrue(image.pixelSize.isPositive)
    }

    func testNormalizedGeometry() {
        let point = NormalizedPoint(x: 0.5, y: 0.25)
        XCTAssertTrue(point.isNormalized)

        let rect = NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4)
        XCTAssertTrue(rect.contains(point))
        XCTAssertFalse(rect.contains(NormalizedPoint(x: 0.9, y: 0.9)))

        let clamped = NormalizedPoint(x: -1, y: 2).clamped()
        XCTAssertEqual(clamped, NormalizedPoint(x: 0, y: 1))
    }

    func testStyleProfileJSONRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let profile = StyleProfile(
            pairCount: 5,
            confidence: .standard,
            tone: ToneParameters(exposure: 0.2, contrast: -0.1, temperature: 0.3),
            skin: SkinParameters(smoothing: 0.35, evenness: 0.2, blemish: 0.1),
            face: FaceParameters(slim: 0.3, jaw: 0.2),
            body: BodyParameters(arm: 0.1, waist: 0.2, leg: 0.15, legLength: 1.05),
            finish: FinishParameters(grain: 0.1, vignette: -0.1),
            tags: ["style.warm", "style.soft"],
            updatedAt: date
        )

        let data = try StyleProfileCoding.makeEncoder().encode(profile)
        let decoded = try StyleProfileCoding.makeDecoder().decode(StyleProfile.self, from: data)
        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.schemaVersion, 3)
    }

    func testStyleProfileMissingFieldsUseDefaults() throws {
        let json = Data(#"{"schemaVersion":3}"#.utf8)
        let profile = try StyleProfileCoding.makeDecoder().decode(StyleProfile.self, from: json)
        XCTAssertEqual(profile.algorithmVersion, StyleProfile.currentAlgorithmVersion)
        XCTAssertEqual(profile.pairCount, 0)
        XCTAssertEqual(profile.confidence, .trial)
        XCTAssertTrue(profile.isNeutral)
    }

    func testStyleProfileRejectsFutureSchema() {
        let json = Data(#"{"schemaVersion":99}"#.utf8)
        XCTAssertThrowsError(try StyleProfileCoding.makeDecoder().decode(StyleProfile.self, from: json))
    }

    func testParameterClamping() {
        let tone = ToneParameters(exposure: 5, contrast: -5)
        XCTAssertEqual(tone.exposure, 1)
        XCTAssertEqual(tone.contrast, -1)

        let body = BodyParameters(legLength: 2)
        XCTAssertEqual(body.legLength, 1.15)

        let blemish = BlemishPoint(point: NormalizedPoint(x: 0.5, y: 0.5), radius: 1)
        XCTAssertEqual(blemish.radius, 0.08)
    }

    func testRenderRequestClampsStrength() throws {
        let image = try TestImageFactory.make()
        let analysis = PortraitAnalysis.empty(imageSize: image.pixelSize)
        let request = RenderRequest(
            image: image,
            analysis: analysis,
            style: .neutral(updatedAt: Date(timeIntervalSince1970: 0)),
            strength: 3
        )
        XCTAssertEqual(request.strength, 1.5)
        XCTAssertTrue(request.backgroundProtection)
        XCTAssertTrue(request.blemishPoints.isEmpty)
    }

    func testAppErrorMapping() {
        let appError = AppError.map(.noFaceDetected)
        XCTAssertEqual(appError.code, "E_NO_FACE")
        XCTAssertEqual(appError.titleKey, "error.noFace.title")
        XCTAssertEqual(appError.recovery, .useNaturalStyle)
        XCTAssertEqual(appError.diagnosticCode, "ST-E_NO_FACE")
    }

    func testMocksConformToProtocols() async throws {
        let image = try TestImageFactory.make()
        let analysis = PortraitAnalysis.empty(imageSize: image.pixelSize)

        let analyzer = MockPortraitAnalyzer(result: .success(analysis))
        let analyzed = try await analyzer.analyze(image)
        XCTAssertEqual(analyzed.imageSize, image.pixelSize)

        let learner = MockStyleLearner(profile: .neutral(updatedAt: Date(timeIntervalSince1970: 0)))
        let profile = try await learner.learn(samples: [], answers: [])
        XCTAssertTrue(profile.isNeutral)

        let purchaser = MockPurchaser()
        let initialState = await purchaser.state
        XCTAssertEqual(initialState, .unknown)
        let purchasedState = try await purchaser.purchase()
        XCTAssertEqual(purchasedState, .active)
    }
}
