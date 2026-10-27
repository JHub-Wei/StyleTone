import Foundation

/// One committed baseline value for one scenario on one environment.
public struct PerformanceBaselineEntry: Codable, Sendable, Equatable, Identifiable {
    /// Composite identity used by tools and reports.
    public var id: String { "\(scenarioID)@\(environmentID)" }

    public let scenarioID: String
    public let environmentID: String
    /// Recorded statistic in `unit` (p50 for CI-noisy scenarios, p95 otherwise).
    public let value: Double
    public let unit: PerformanceUnit
    /// Statistic represented by `value`; must match the scenario's regression
    /// statistic. Contract budgets still use p95 independently.
    public let statistic: PerformanceStatistic
    /// Number of samples behind `value`.
    public let sampleCount: Int
    /// ISO-8601 timestamp of the recording.
    public let recordedAt: String
    /// Commit that was measured; `unknown` for manual device runs before merge.
    public let commit: String
    /// CI run URL, device label or other traceability string.
    public let source: String
    public let notes: String?
    /// When `false` the value is informational and never blocks a build.
    public let gateEnabled: Bool

    public init(
        scenarioID: String,
        environmentID: String,
        value: Double,
        unit: PerformanceUnit,
        statistic: PerformanceStatistic = .p95,
        sampleCount: Int,
        recordedAt: String,
        commit: String,
        source: String,
        notes: String? = nil,
        gateEnabled: Bool = true
    ) {
        self.scenarioID = scenarioID
        self.environmentID = environmentID
        self.value = value
        self.unit = unit
        self.statistic = statistic
        self.sampleCount = max(0, sampleCount)
        self.recordedAt = recordedAt
        self.commit = commit
        self.source = source
        self.notes = notes
        self.gateEnabled = gateEnabled
    }
}

/// Versioned baseline document stored in the repository.
///
/// Baselines are grouped by environment because absolute performance is not a
/// CI invariant (contracts §7.1). A run may only be compared with an entry for
/// exactly the same environment and build configuration.
public struct PerformanceBaselineFile: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    /// ISO-8601 timestamp of the last edit.
    public let generatedAt: String
    /// Human readable reference device, e.g. `iPhone 13`.
    public let referenceDevice: String
    public let notes: String?
    public let entries: [PerformanceBaselineEntry]

    public init(
        schemaVersion: Int = PerformanceBaselineFile.currentSchemaVersion,
        generatedAt: String,
        referenceDevice: String,
        notes: String? = nil,
        entries: [PerformanceBaselineEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.referenceDevice = referenceDevice
        self.notes = notes
        self.entries = entries
    }

    /// Looks up the baseline for one scenario and environment.
    public func entry(
        scenarioID: String,
        environmentID: String
    ) -> PerformanceBaselineEntry? {
        entries.first {
            $0.scenarioID == scenarioID && $0.environmentID == environmentID
        }
    }

    /// Returns a copy with `entry` inserted or replacing the existing pair.
    public func upserting(_ entry: PerformanceBaselineEntry) -> PerformanceBaselineFile {
        var next = entries.filter {
            !($0.scenarioID == entry.scenarioID && $0.environmentID == entry.environmentID)
        }
        next.append(entry)
        next.sort {
            if $0.environmentID != $1.environmentID {
                return $0.environmentID < $1.environmentID
            }
            return $0.scenarioID < $1.scenarioID
        }
        return PerformanceBaselineFile(
            schemaVersion: schemaVersion,
            generatedAt: entry.recordedAt,
            referenceDevice: referenceDevice,
            notes: notes,
            entries: next
        )
    }

    /// Decodes and validates a baseline document.
    public static func decode(_ data: Data) throws -> PerformanceBaselineFile {
        let file: PerformanceBaselineFile
        do {
            file = try JSONDecoder().decode(PerformanceBaselineFile.self, from: data)
        } catch {
            throw PerformanceKitError.invalidBaseline(
                "JSON decoding failed: \(error.localizedDescription)"
            )
        }
        try file.validate()
        return file
    }

    /// Encodes the document with sorted keys so diffs stay reviewable.
    public func encoded(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(self)
        } catch {
            throw PerformanceKitError.reportEncodingFailed(error.localizedDescription)
        }
    }

    /// Validates schema, units, values and uniqueness.
    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PerformanceKitError.unsupportedSchemaVersion(schemaVersion)
        }
        guard !referenceDevice.isEmpty else {
            throw PerformanceKitError.invalidBaseline("referenceDevice is empty")
        }
        var seen = Set<String>()
        for entry in entries {
            guard !entry.scenarioID.isEmpty, !entry.environmentID.isEmpty else {
                throw PerformanceKitError.invalidBaseline(
                    "scenarioID and environmentID must not be empty"
                )
            }
            guard entry.value.isFinite, entry.value >= 0 else {
                throw PerformanceKitError.invalidBaseline(
                    "\(entry.id) has a non-finite or negative value"
                )
            }
            guard entry.sampleCount > 0 else {
                throw PerformanceKitError.invalidBaseline(
                    "\(entry.id) has no samples"
                )
            }
            guard entry.recordedAt.isEmpty == false else {
                throw PerformanceKitError.invalidBaseline(
                    "\(entry.id) has no recordedAt timestamp"
                )
            }
            guard let scenario = PerformanceScenario.scenario(id: entry.scenarioID) else {
                throw PerformanceKitError.invalidBaseline(
                    "unknown scenario \(entry.scenarioID)"
                )
            }
            guard scenario.unit == entry.unit else {
                throw PerformanceKitError.invalidBaseline(
                    "\(entry.id) uses \(entry.unit.rawValue) but the scenario uses "
                        + scenario.unit.rawValue
                )
            }
            guard scenario.regressionStatistic == entry.statistic else {
                throw PerformanceKitError.invalidBaseline(
                    "\(entry.id) records \(entry.statistic.rawValue) but the scenario "
                        + "regresses on \(scenario.regressionStatistic.rawValue)"
                )
            }
            guard seen.insert(entry.id).inserted else {
                throw PerformanceKitError.duplicateBaseline(
                    scenarioID: entry.scenarioID,
                    environmentID: entry.environmentID
                )
            }
        }
    }
}
