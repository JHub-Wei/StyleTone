import Foundation

public enum LogLevel: String, Sendable, CaseIterable {
    case debug
    case info
    case warning
    case error
}

/// Logging boundary. Implementations must not log photos, file names,
/// photo-library identifiers or other PII.
public protocol AppLogging: Sendable {
    func log(_ level: LogLevel, _ message: String, metadata: [String: String])
}

public struct NoopLogger: AppLogging {
    public init() {}
    public func log(_ level: LogLevel, _ message: String, metadata: [String: String]) {}
}
