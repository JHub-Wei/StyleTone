import Foundation
import ImageIO
import StyleToneCore
import StyleToneUI
import TestShared
import UniformTypeIdentifiers
import XCTest

/// The real decode path behind the picker: bounds, source size and errors.
final class PairingImageImporterTests: XCTestCase {
    private let date = PairingTestFactory.referenceDate

    func testImportBoundsTheProxyAndKeepsSourceSize() async throws {
        let source = try MockImageAssetFactory.solid(
            size: PixelSize(width: 256, height: 192)
        )
        let data = try Self.pngData(from: source)
        let importer = PairingImageImporter(
            configuration: PairingImportConfiguration(
                maximumLongEdge: 128,
                minimumLongEdge: 1
            )
        )

        let photo = try await importer.importImage(
            from: data,
            sourceIdentifier: "asset-1",
            importedAt: date
        )

        XCTAssertEqual(photo.sourcePixelSize, PixelSize(width: 256, height: 192))
        XCTAssertEqual(photo.displayPixelSize.longEdge, 128)
        XCTAssertEqual(photo.displayPixelSize.shortEdge, 96)
        XCTAssertEqual(photo.sourceIdentifier, "asset-1")
        XCTAssertEqual(photo.byteCount, data.count)
        XCTAssertEqual(photo.importedAt, date)
    }

    func testImportRejectsSourceBelowMinimum() async throws {
        let source = try MockImageAssetFactory.solid(
            size: PixelSize(width: 64, height: 64)
        )
        let data = try Self.pngData(from: source)
        let importer = PairingImageImporter(
            configuration: PairingImportConfiguration(
                maximumLongEdge: 512,
                minimumLongEdge: 128
            )
        )

        do {
            _ = try await importer.importImage(
                from: data,
                sourceIdentifier: nil,
                importedAt: date
            )
            XCTFail("a 64 px source must be rejected")
        } catch {
            XCTAssertEqual(
                error as? PairingImportError,
                .imageTooSmall(minimumLongEdge: 128)
            )
        }
    }

    func testImportRejectsGarbagePayload() async throws {
        let importer = PairingImageImporter(
            configuration: PairingImportConfiguration(minimumLongEdge: 1)
        )

        do {
            _ = try await importer.importImage(
                from: Data([0x00, 0x01, 0x02, 0x03]),
                sourceIdentifier: nil,
                importedAt: date
            )
            XCTFail("garbage must not decode")
        } catch {
            XCTAssertEqual(error as? PairingImportError, .decodingFailed)
        }
    }

    func testImportRejectsEmptyPayload() async throws {
        let importer = PairingImageImporter()
        do {
            _ = try await importer.importImage(
                from: Data(),
                sourceIdentifier: nil,
                importedAt: date
            )
            XCTFail("empty data must not decode")
        } catch {
            XCTAssertEqual(error as? PairingImportError, .noImageData)
        }
    }

    // MARK: - Helpers

    private static func pngData(from asset: ImageAsset) throws -> Data {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("styletone-pairing-\(UUID().uuidString)", isDirectory: false)
            .appendingPathExtension("png")
        defer { try? FileManager.default.removeItem(at: url) }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw PairingImportError.unknown
        }
        CGImageDestinationAddImage(destination, asset.cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PairingImportError.unknown
        }
        return try Data(contentsOf: url)
    }
}
