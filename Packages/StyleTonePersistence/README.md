# StyleTonePersistence (WP-08)

Local-only persistence for the personalized style profile, edit metadata,
calibration sessions and the free-export quota. The package depends only on
`StyleToneCore`; it has no account, network, photo-library or StoreKit code and
never stores image pixels.

## Storage layout

```text
<base>/                                default: Application Support/StyleTone
├── style-index.store                  SwiftData index (metadata rows only)
├── style-profiles/{uuid}.json         canonical StyleProfile documents
├── style-profile-migration-backups/   originals superseded by a migration
├── style-profile-recovery/            quarantined unreadable profiles
├── style-index-recovery/              quarantined SwiftData stores
└── style-thumbnails/                  owned by UI/Imaging; deleted with all data
```

The JSON document is the source of truth. SwiftData only indexes it, so a
damaged index can be discarded and rebuilt from the JSON files without losing
the user's profile.

## Public surface

| Type | Purpose |
|---|---|
| `SwiftDataStyleProfileStore` | Actor implementing `StyleProfileStore` plus local metadata APIs |
| `PersistenceConfiguration` | Base directory and file-protection class |
| `PersistenceFileSystem` / `LocalPersistenceFileSystem` | Injectable file-system boundary |
| `StylePersistenceError` | Path-free errors with `AppError` mapping |
| `StyleProfileJSONMigrator` | Tolerant schema 1/2/3 decoder + canonical encoder |
| `StyleProfileSanitizer` | Clamps values, repairs metadata before writes |
| `StyleProfileRecord` / `EditRecord` / `PairSessionRecord` / `QuotaRecord` | SwiftData models |
| `StyleProfileMetadata`, `EditDraft`, `EditRecordSnapshot` | `Sendable` values crossing the actor boundary |
| `PairSessionDraft`, `PairSessionSnapshot`, `QuotaSnapshot` | `Sendable` values crossing the actor boundary |

```swift
let store = SwiftDataStyleProfileStore(
    configuration: PersistenceConfiguration() // .complete file protection
)

try await store.save(profile)
let active = try await store.loadActive()
let metadata = try await store.activeProfileMetadata()

_ = try await store.recordEdit(
    EditDraft(inputReference: opaquePhotoToken, adjustments: adjustments)
)
_ = try await store.recordSuccessfulExport()
let quota = try await store.quota()

try await store.deleteAll()   // profiles, edits, sessions, quota, caches
```

Profile JSON follows the shared contract: `JSONEncoder` with `sortedKeys`,
ISO8601 dates, `schemaVersion = 3`, `algorithmVersion = st-3.0.0`.

## Models

- **StyleProfileRecord**: `id`, `fileName`, `schemaVersion`, `algorithmVersion`,
  `pairCount`, `confidenceRawValue`, `tagKeys`, `createdAt`, `updatedAt`,
  `isActive`. Unique `id`; exactly one active row per profile switch.
- **EditRecord**: `id`, optional `styleID`, opaque `inputReference`,
  `adjustmentsData` (JSON-encoded `ManualAdjustments`), `createdAt`, `exported`,
  `exportedAt`. No pixels, filenames or photo-library identifiers.
- **PairSessionRecord**: `id`, opaque `pairReferences`, `targetPairCount`,
  `abChoiceCount`, `statusRawValue`, `createdAt`, `updatedAt`.
- **QuotaRecord**: singleton `key`, `freeExportsUsed`, `updatedAt`. The free
  limit (3) lives in `QuotaSnapshot`; a successful export increments the row.

Write paths are serialized by the actor, so concurrent saves reuse the active
UUID and leave one profile file. `deleteAll` clears all four tables and every
data directory.

## Migration strategy

`StyleProfileJSONMigrator` reads the raw JSON first, then applies legacy repairs
before decoding with the Core decoder. Core types already supply defaults for
missing fields and clamp numeric ranges.

| Stored document | Behaviour |
|---|---|
| `schemaVersion` missing | treated as schema 1 |
| schema 1 | `tone.temp` → `tone.temperature`; metadata repaired; rewritten as 3 |
| schema 2 | same legacy repair; missing `finish`/`tags` default; rewritten as 3 |
| schema 3 | decoded as-is; only non-canonical dates/metadata normalized in memory |
| schema > 3 | `profileUnsupportedSchema(version:)`; file untouched; recalibrate prompt |
| unreadable JSON / empty file | `profileCorrupt`; file untouched; recalibrate prompt |
| structurally damaged legacy document | `profileMigrationFailed(sourceVersion:)`; file untouched |
| current schema with wrong field types | `profileCorrupt`; file untouched |

Before a migrated document is rewritten, the original bytes are copied to
`style-profile-migration-backups/<uuid>-v<source>-<timestamp>.json`. A failed
migration never overwrites the original. Dates accept ISO8601 (with or without
fractional seconds) and numeric epochs; unusable dates fall back to the injected
clock instead of failing the whole profile.

Errors map to the shared `AppError` contract through
`StylePersistenceError.appError`: corrupt/newer/migration failures use the
schema error and recommend recalibration; I/O and index failures recommend retry.
`quarantineActiveProfile()` moves a bad profile aside and clears its active flag
so the user can recalibrate without losing edits, sessions or quota.

### Index recovery

If the SwiftData store cannot be opened or queried, its files are moved to
`style-index-recovery/index-<timestamp>-<suffix>/` and a fresh index is built.
The next `loadActive()` scans `style-profiles/*.json`, migrates each valid file,
selects the newest `updatedAt`, and recreates the active row. A missing active
file deactivates the stale row and falls back to the same scan; no profile is
ever deleted by index repair.

## Deletion

`deleteAll()`:

1. deletes all rows in the four SwiftData models and saves;
2. releases the container;
3. removes profile JSON, thumbnails, migration backups, profile quarantine and
   index quarantine directories;
4. unlinks `style-index.store` plus its SQLite sidecars when possible.

If the store file itself cannot be unlinked, it no longer contains any user row;
the method still reports success after every data artifact is gone. Quota rows
are reset by the same operation (allowed by the product contract).

## File protection and privacy

- Every profile, backup and thumbnail file is written with
  `PersistenceFileProtection.complete` (default; configurable).
- On iOS/tvOS/watchOS/visionOS the file system applies
  `FileAttributeKey.protectionKey` to files and directories. macOS has no
  per-file protection classes, so the local implementation is a no-op there;
  the requested class remains observable through the injected file system.
- Reads/writes are atomic (`Data.write(options: .atomic)`); protection is applied
  immediately after each write.
- No `URLSession`, CloudKit, StoreKit, authentication, photo-library or image
  APIs exist in the module. `ModelConfiguration` explicitly sets
  `cloudKitDatabase: .none`.
- Logging goes through the Core `AppLogging` boundary and never includes paths,
  filenames, photo identifiers or user text.

## Concurrency and main-thread I/O

`SwiftDataStyleProfileStore` is an `actor`. Every protocol call is serialized,
and all file/SwiftData work happens on the actor executor. The initializer only
stores configuration; directories and the SwiftData container are created
lazily on the first operation. `PersistenceFileProtectionTests` records the
executing thread of every file operation and asserts none runs on the main
thread.

## Tests

```bash
swift test --filter StyleTonePersistenceTests
```

Coverage:

- CRUD, restart persistence, stable active identity, metadata, missing-file
  fallback;
- schema 1/2 migration, missing `schemaVersion`, fractional dates, backups,
  newer schema, malformed/empty JSON, structural damage;
- corrupt profile quarantine and recalibration path;
- corrupt SwiftData index recovery and rebuild from JSON;
- delete-all residue (JSON, thumbnails, backups, quarantine, index file), quota
  reset, restart after deletion;
- edit/session/quota CRUD and restart persistence;
- concurrent saves/loads/quota increments/edits;
- file-protection propagation and no main-thread file operations;
- source audit for network/account/photo APIs.

## Known risks / open items

- **CI verification is pending.** The Windows session has no Swift/Xcode
  toolchain; `swift test` and the iOS simulator build must run on the macOS CI
  branch (`CI_PENDING`).
- SwiftData's on-disk schema is not versioned yet. The JSON schema is versioned
  (contract §6); a future SwiftData model change should add a `VersionedSchema`
  plus `SchemaMigrationPlan`. Index data is disposable and can be rebuilt.
- File protection is applied per file. The App target should also set the
  `NSFileProtectionComplete` default data-protection entitlement as
  defense-in-depth; this package cannot add entitlements.
- Quarantine/backup directories retain copies until `deleteAll`. They are
  included in the deletion path, but their growth is not otherwise bounded
  (migration/quarantine events are rare).
- Profile JSON writes are atomic, but the file + index update is not one
  transaction. A crash between the two leaves an orphan JSON or a stale metadata
  row; both are self-healing on the next load.
