import CoreGraphics
import Foundation
import ImageIO
import StyleToneCore
import StyleToneUI
import TestShared
import XCTest

// MARK: - Renderers

/// Renderer that walks a scripted list of steps.
actor ScriptedRenderer: ImageRendering {
    enum Step: Sendable {
        case echo
        case sized(PixelSize)
        case failure(StyleToneError)
    }

    private var steps: [Step]
    private(set) var callCount = 0
    private(set) var receivedPixelSizes: [PixelSize] = []

    init(steps: [Step] = []) {
        self.steps = steps
    }

    func render(_ request: RenderRequest) async throws -> RenderOutput {
        callCount += 1
        receivedPixelSizes.append(request.image.pixelSize)

        let step: Step
        if steps.isEmpty {
            step = .echo
        } else {
            step = steps.removeFirst()
        }

        switch step {
        case .echo:
            return RenderOutput(image: request.image)
        case let .sized(size):
            let image = try MockImageAssetFactory.solid(size: size)
            return RenderOutput(image: image)
        case let .failure(error):
            throw error
        }
    }
}

/// Gate that lets a test observe an in-flight stage deterministically.
actor RenderGate {
    private var entered = false
    private var isOpen = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var waitContinuation: CheckedContinuation<Void, Never>?

    func markEnteredAndWait() async {
        entered = true
        if let continuation = enteredContinuation {
            enteredContinuation = nil
            continuation.resume()
        }
        if isOpen {
            return
        }
        await withCheckedContinuation { continuation in
            waitContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        if entered {
            return
        }
        await withCheckedContinuation { continuation in
            enteredContinuation = continuation
        }
    }

    func open() {
        isOpen = true
        if let continuation = waitContinuation {
            waitContinuation = nil
            continuation.resume()
        }
    }
}

/// Renderer that blocks until the test opens its gate.
struct GatedRenderer: ImageRendering {
    let gate: RenderGate
    let image: ImageAsset?

    init(gate: RenderGate, image: ImageAsset? = nil) {
        self.gate = gate
        self.image = image
    }

    func render(_ request: RenderRequest) async throws -> RenderOutput {
        await gate.markEnteredAndWait()
        return RenderOutput(image: image ?? request.image)
    }
}

// MARK: - Photo library doubles

/// Add-only library double with deterministic authorization and save behavior.
actor FakePhotoLibrary: ExportPhotoLibrary {
    private var status: PhotoLibraryAccess
    private var requestResult: PhotoLibraryAccess
    private var saveError: ExportLibraryError?

    private(set) var authorizationCount = 0
    private(set) var requestCount = 0
    private(set) var saveCount = 0
    private(set) var savedFiles: [ExportStagedFile] = []

    init(
        status: PhotoLibraryAccess = .authorized,
        requestResult: PhotoLibraryAccess? = nil,
        saveError: ExportLibraryError? = nil
    ) {
        self.status = status
        self.requestResult = requestResult ?? status
        self.saveError = saveError
    }

    func authorizationStatus() async -> PhotoLibraryAccess {
        authorizationCount += 1
        return status
    }

    func requestAddOnlyAccess() async -> PhotoLibraryAccess {
        requestCount += 1
        status = requestResult
        return requestResult
    }

    func save(_ file: ExportStagedFile) async throws {
        saveCount += 1
        if let saveError {
            throw saveError
        }
        savedFiles.append(file)
    }

    func setStatus(_ value: PhotoLibraryAccess) {
        status = value
    }

    func setRequestResult(_ value: PhotoLibraryAccess) {
        requestResult = value
    }

    func setSaveError(_ value: ExportLibraryError?) {
        saveError = value
    }
}

/// Library double whose save blocks until the test opens the gate.
actor GatedPhotoLibrary: ExportPhotoLibrary {
    private let gate: RenderGate
    private var status: PhotoLibraryAccess

    private(set) var saveCount = 0
    private(set) var savedFiles: [ExportStagedFile] = []

    init(gate: RenderGate, status: PhotoLibraryAccess = .authorized) {
        self.gate = gate
        self.status = status
    }

    func authorizationStatus() async -> PhotoLibraryAccess {
        status
    }

    func requestAddOnlyAccess() async -> PhotoLibraryAccess {
        status
    }

    func save(_ file: ExportStagedFile) async throws {
        saveCount += 1
        await gate.markEnteredAndWait()
        savedFiles.append(file)
    }
}

// MARK: - Quota

/// Entitlement/count double with call counters and injectable failures.
actor FakeExportQuota: ExportQuotaServicing {
    private var current: ExportEntitlement
    private var entitlementError: StyleToneError?
    private var recordError: StyleToneError?

    private(set) var entitlementCount = 0
    private(set) var recordCount = 0

    init(
        _ entitlement: ExportEntitlement = .unlimited,
        entitlementError: StyleToneError? = nil,
        recordError: StyleToneError? = nil
    ) {
        self.current = entitlement
        self.entitlementError = entitlementError
        self.recordError = recordError
    }

    func entitlement() async throws -> ExportEntitlement {
        entitlementCount += 1
        if let entitlementError {
            throw entitlementError
        }
        return current
    }

    func recordSuccessfulExport() async throws {
        recordCount += 1
        if let recordError {
            throw recordError
        }
    }

    func setEntitlement(_ value: ExportEntitlement) {
        current = value
    }

    func setEntitlementError(_ value: StyleToneError?) {
        entitlementError = value
    }

    func setRecordError(_ value: StyleToneError?) {
        recordError = value
    }
}

// MARK: - Exporter

/// File-writing `ImageExporting` double with scripted failures and overrides.
///
/// Writes a real ImageIO-encoded image so the view model's encoded-file
/// inspector sees truthful dimensions and format. `setSizeOverride` changes the
/// file that is written; `setReportedSizeOverride` changes only the metadata the
/// exporter returns, which lets a test prove the inspector catches a lying
/// exporter.
///
/// A plain lock-free reference type is deliberate: the double is only driven
/// from the main actor in these tests, and avoiding an actor removes an
/// additional executor from the async test teardown path.
final class FileWritingExporter: ImageExporting, @unchecked Sendable {
    private let directory: URL
    private var failures: [StyleToneError?]
    private var writeSizeOverride: PixelSize?
    private var reportedSizeOverride: PixelSize?
    private var formatOverride: ExportFormat?
    private var removesOutput = false

    private(set) var callCount = 0
    private(set) var receivedPixelSizes: [PixelSize] = []
    private(set) var receivedOptions: [ExportOptions] = []
    private(set) var writtenURLs: [URL] = []

    init(directory: URL, failures: [StyleToneError?] = []) {
        self.directory = directory
        self.failures = failures
    }

    func setSizeOverride(_ value: PixelSize?) {
        writeSizeOverride = value
    }

    func setReportedSizeOverride(_ value: PixelSize?) {
        reportedSizeOverride = value
    }

    func setFormatOverride(_ value: ExportFormat?) {
        formatOverride = value
    }

    func setRemovesOutput(_ value: Bool) {
        removesOutput = value
    }

    func export(_ output: ImageAsset, options: ExportOptions) async throws -> ExportResult {
        callCount += 1
        receivedPixelSizes.append(output.pixelSize)
        receivedOptions.append(options)

        if !failures.isEmpty {
            let failure = failures.removeFirst()
            if let failure {
                throw failure
            }
        }

        let actualSize = writeSizeOverride ?? output.pixelSize
        let actualFormat = formatOverride ?? options.format
        let fileExtension = actualFormat == .heic ? "heic" : "jpg"
        let url = directory
            .appendingPathComponent("encoded-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
        try Self.writeImage(
            to: url,
            size: actualSize,
            format: actualFormat,
            quality: options.quality
        )

        if removesOutput {
            try FileManager.default.removeItem(at: url)
        } else {
            writtenURLs.append(url)
        }

        return ExportResult(
            url: url,
            pixelSize: reportedSizeOverride ?? actualSize,
            format: actualFormat
        )
    }

    private static func writeImage(
        to url: URL,
        size: PixelSize,
        format: ExportFormat,
        quality: Double
    ) throws {
        guard size.isPositive,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            throw StyleToneError.exportFailed
        }
        guard let context = CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw StyleToneError.exportFailed
        }

        let fill = CGColor(colorSpace: colorSpace, components: [0.5, 0.5, 0.5, 1])
            ?? CGColor(gray: 0.5, alpha: 1)
        context.setFillColor(fill)
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        guard let image = context.makeImage() else {
            throw StyleToneError.exportFailed
        }

        let typeIdentifier = format == .heic ? "public.heic" : "public.jpeg"
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            typeIdentifier as CFString,
            1,
            nil
        ) else {
            throw StyleToneError.exportFailed
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: min(max(quality, 0), 1)
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw StyleToneError.exportFailed
        }
    }
}

// MARK: - Factory

enum ExportTestFactory {
    static let referenceDate = Date(timeIntervalSince1970: 1_767_225_600)
    static let defaultSize = PixelSize(width: 640, height: 480)

    /// HEIC when the host ImageIO can encode it, JPEG otherwise.
    ///
    /// Success-path tests write real encoded files, so they must follow the
    /// platform codec rather than hard-failing on a JPEG-only runner.
    static let defaultFormat: ExportFormat = {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return identifiers.contains("public.heic") ? .heic : .jpeg
    }()

    static func source(
        size: PixelSize = defaultSize,
        previewSize: PixelSize? = nil,
        expectedPixelSize: PixelSize? = nil
    ) throws -> ExportSource {
        let image = try MockImageAssetFactory.solid(size: size)
        let analysis = try MockPortraitAnalysisFactory.portrait(
            size: size,
            includesMasks: false
        )
        let request = RenderRequest(
            image: image,
            analysis: analysis,
            style: MockStyleProfileFactory.standard(updatedAt: referenceDate)
        )

        var preview: ImageAsset?
        if let previewSize {
            preview = try MockImageAssetFactory.solid(size: previewSize)
        }

        return ExportSource(
            request: request,
            preview: preview,
            expectedPixelSize: expectedPixelSize
        )
    }

    @MainActor
    static func dependencies(
        directory: URL,
        renderer: any ImageRendering = MockImageRenderer.echo(),
        exporter: any ImageExporting,
        photoLibrary: any ExportPhotoLibrary = FakePhotoLibrary(),
        quota: any ExportQuotaServicing = FakeExportQuota(),
        supportsShare: Bool = true,
        staleAfter: TimeInterval = 600
    ) -> ExportDependencies {
        ExportDependencies(
            renderer: renderer,
            exporter: exporter,
            photoLibrary: photoLibrary,
            quota: quota,
            logger: NoopLogger(),
            dateProvider: FixedDateProvider(referenceDate),
            fileStore: ExportTemporaryFileStore(
                directory: directory,
                staleAfter: staleAfter
            ),
            supportsSystemShare: supportsShare
        )
    }

    @MainActor
    static func model(
        directory: URL,
        size: PixelSize = defaultSize,
        renderer: any ImageRendering = MockImageRenderer.echo(),
        exporter: any ImageExporting,
        photoLibrary: any ExportPhotoLibrary = FakePhotoLibrary(),
        quota: any ExportQuotaServicing = FakeExportQuota(),
        settings: ExportSettings = ExportSettings(format: ExportTestFactory.defaultFormat),
        supportsShare: Bool = true,
        staleAfter: TimeInterval = 600
    ) throws -> ExportViewModel {
        ExportViewModel(
            source: try source(size: size),
            dependencies: dependencies(
                directory: directory,
                renderer: renderer,
                exporter: exporter,
                photoLibrary: photoLibrary,
                quota: quota,
                supportsShare: supportsShare,
                staleAfter: staleAfter
            ),
            settings: settings
        )
    }

    static func directoryContents(_ directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }
}
