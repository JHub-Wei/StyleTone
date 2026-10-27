import Foundation

#if canImport(Photos) && os(iOS)
import Photos
#endif

// MARK: - Access

/// Add-only photo-library access state.
///
/// The export flow never requests read access. `.limited` can be reported by
/// iOS when the user already granted limited read/write access; it still allows
/// adding, so it counts as usable here. `.unavailable` means this build cannot
/// ask (for example the app is missing `NSPhotoLibraryAddUsageDescription`);
/// failing closed is safer than crashing inside PhotoKit.
public enum PhotoLibraryAccess: String, Sendable, Equatable, CaseIterable {
    case notDetermined
    case authorized
    case limited
    case denied
    case restricted
    case unavailable

    public var canAddPhotos: Bool {
        self == .authorized || self == .limited
    }

    public var isDenied: Bool {
        self == .denied || self == .restricted
    }

    public var isUnavailable: Bool {
        self == .unavailable
    }

    public var canRequestAccess: Bool {
        self == .notDetermined
    }
}

// MARK: - Errors

/// Low-level photo-library failures. They map to user copy in `ExportFailure`.
public enum ExportLibraryError: Error, Sendable, Equatable {
    case permissionDenied
    case permissionRestricted
    case saveFailed
    case unavailable

    public var code: String {
        switch self {
        case .permissionDenied: return "E_LIBRARY_PERMISSION"
        case .permissionRestricted: return "E_LIBRARY_RESTRICTED"
        case .saveFailed: return "E_LIBRARY_SAVE"
        case .unavailable: return "E_LIBRARY_UNAVAILABLE"
        }
    }
}

// MARK: - Protocol

/// Add-only photo-library boundary.
///
/// Implementations must never fetch assets, read thumbnails or inspect the
/// library. `save` copies the already-encoded file into Photos; the caller owns
/// the temporary file and deletes it after the save completes.
public protocol ExportPhotoLibrary: Sendable {
    func authorizationStatus() async -> PhotoLibraryAccess
    func requestAddOnlyAccess() async -> PhotoLibraryAccess
    func save(_ file: ExportStagedFile) async throws
}

// MARK: - Unavailable

/// Fail-closed implementation for previews and builds without PhotoKit.
public struct UnavailableExportPhotoLibrary: ExportPhotoLibrary, Sendable {
    public init() {}

    public func authorizationStatus() async -> PhotoLibraryAccess {
        .unavailable
    }

    public func requestAddOnlyAccess() async -> PhotoLibraryAccess {
        .unavailable
    }

    public func save(_ file: ExportStagedFile) async throws {
        throw ExportLibraryError.unavailable
    }
}

// MARK: - PhotoKit

#if canImport(Photos) && os(iOS)

/// PhotoKit implementation restricted to `PHAssetCreationRequest`.
///
/// No asset fetches, fetch options or image-manager reads; the only
/// authorization requested is `.addOnly`. The app must declare
/// `NSPhotoLibraryAddUsageDescription`; otherwise the implementation reports
/// `.unavailable` instead of calling the privacy-sensitive API and crashing.
public struct PhotoKitExportPhotoLibrary: ExportPhotoLibrary, Sendable {
    public init() {}

    public func authorizationStatus() async -> PhotoLibraryAccess {
        Self.currentAccess()
    }

    public func requestAddOnlyAccess() async -> PhotoLibraryAccess {
        guard Self.hasUsageDescription else {
            return .unavailable
        }
        return await withCheckedContinuation {
            (continuation: CheckedContinuation<PhotoLibraryAccess, Never>) in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: PhotoLibraryAccess(photoKitStatus: status))
            }
        }
    }

    public func save(_ file: ExportStagedFile) async throws {
        guard Self.hasUsageDescription else {
            throw ExportLibraryError.unavailable
        }

        let access = Self.currentAccess()
        switch access {
        case .authorized, .limited:
            break
        case .restricted:
            throw ExportLibraryError.permissionRestricted
        case .denied, .notDetermined:
            throw ExportLibraryError.permissionDenied
        case .unavailable:
            throw ExportLibraryError.unavailable
        }

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                // The caller still needs the file for sharing and cleanup.
                options.shouldMoveFile = false
                request.addResource(with: .photo, fileURL: file.url, options: options)
            }, completionHandler: { success, _ in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ExportLibraryError.saveFailed)
                }
            })
        }
    }

    // MARK: Private

    private static var hasUsageDescription: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryAddUsageDescription") != nil
    }

    private static func currentAccess() -> PhotoLibraryAccess {
        guard hasUsageDescription else {
            return .unavailable
        }
        return PhotoLibraryAccess(
            photoKitStatus: PHPhotoLibrary.authorizationStatus(for: .addOnly)
        )
    }
}

private extension PhotoLibraryAccess {
    init(photoKitStatus status: PHAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .restricted:
            self = .restricted
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        case .limited:
            self = .limited
        @unknown default:
            self = .unavailable
        }
    }
}

#endif
