# TestShared — shared test doubles

`TestShared` provides the protocol mocks and test-session helpers that the WP-04
task card requires (analysis / style / purchase / image), plus a few utilities
that every module test needs. It depends on `StyleToneCore` and `GoldenSupport`
and is **XCTest-free**, so it can be linked from any test target.

```swift
import TestShared
```

Every module test target in `Package.swift` already depends on `TestShared` and
`GoldenSupport`; adding the `import` is all a module owner has to do.

## Test doubles

| type | protocol | behaviour |
|---|---|---|
| `MockPortraitAnalyzer` | `PortraitAnalyzing` | fixed analysis, generated analysis (0–3 faces, masks), or failure |
| `MockPairQualityAnalyzer` | `PairQualityAnalyzing` | fixed grade or failure |
| `MockStyleLearner` | `StyleLearning` | fixed profile or failure |
| `RecordingStyleLearner` | `StyleLearning` | records batch sizes, then returns a fixed profile |
| `MockPurchaser` | `PurchaseServicing` | unknown → active, restore, counters, failure points |
| `MockStyleProfileStore` | `StyleProfileStore` | in-memory save/load/delete, counters, failure points |
| `MockImageRenderer` | `ImageRendering` | closure-backed; `.echo()` / `.failing()` |
| `MockImageExporter` | `ImageExporting` | `.succeeding()` / `.failing()` (does not write a file) |
| `MockRetoucher` | `RetouchRendering` | `.passthrough()` / `.failing()` |
| `MockBlemishRemover` | `BlemishRemoving` | `.passthrough()` / `.failing()` |
| `MockGeometryRenderer` | `GeometryRendering` | `.passthrough()` / `.failing()` |

Image data comes from `MockImageAssetFactory`:

```swift
let solid = try MockImageAssetFactory.solid(color: .midGray, size: PixelSize(width: 64, height: 64))
let gradient = try MockImageAssetFactory.gradient(from: .black, to: .white)
let checker = try MockImageAssetFactory.checkerboard(cellSize: 8)
let fixture = try MockImageAssetFactory.fixture(named: "colorchart.skintones")
let broken = MockImageAssetFactory.corruptedPNGData() // decode-failure input
```

## Analysis fixtures

`MockPortraitAnalysisFactory` produces a deterministic portrait for any size:

```swift
let analysis = try MockPortraitAnalysisFactory.portrait(
    size: PixelSize(width: 1080, height: 1440),
    faceCount: 1,
    includesBody: true,
    includesMasks: true
)
```

- One to three faces with all ten `FaceLandmarkKind` cases populated.
- All thirteen `BodyJointKind` joints.
- Full-size person/skin/background-edge masks.
- `noFace`, `multipleFaces` and `noBody` warnings derived from the arguments.
- `MockMaskFactory` builds solid, soft ellipse, rectangle and border masks for
  retouch/geometry tests.

**Coordinate convention:** mock landmarks and masks use a **top-left origin**
with y growing downwards. Vision emits bottom-left normalized coordinates, so
WP-05 must convert before producing `PortraitAnalysis`; the Core contract does
not fix an origin. This is the one convention a module owner must double-check.

## Profiles

`MockStyleProfileFactory` provides deterministic profiles:

- `natural()` — neutral, pairCount 0, `.trial`.
- `trial()` — 3 pairs, `.trial`.
- `standard()` — 5 pairs, `.standard`, mild tone/skin/face/body values.
- `stable()` — 8 pairs, `.stable`.
- `extreme()` — every parameter at its legal maximum, for clamping tests.

All use `FixedDateProvider.reference` (2026-01-01T00:00:00Z) unless a date is
passed, so JSON comparisons stay deterministic.

## Session helpers

| helper | purpose |
|---|---|
| `TestEnvironment` | locates the repository (`ST_REPO_ROOT` or walk-up), exposes `Fixtures/manifest.json`, reference PNGs and the sample manifest |
| `TemporaryDirectory` | unique temp dir with cleanup (`withTemporaryDirectory` / `withTemporaryDirectoryAsync`) |
| `FixedDateProvider` | immutable `DateProviding` |
| `AdjustableTestClock` | thread-safe clock that can be advanced (expiry tests without sleeping) |

`TestEnvironment` is how tests reach committed fixture PNGs:

```swift
let environment = TestEnvironment()
guard let referenceDirectory = environment.referenceDirectory else {
    throw XCTSkip("repository root not found; set ST_REPO_ROOT")
}
```

## Rules

- No network, no real photos, no filesystem writes outside a
  `TemporaryDirectory`.
- No `sleep`-based timing: use `AdjustableTestClock` or an injected clock.
- Mocks return immediately; add delays only in UI tests that genuinely need
  them, and never in unit tests.
- `MockImageExporter` returns a plausible `ExportResult` but writes nothing;
  use the real exporter when bytes matter.
- Extend the mocks here rather than copying them into each module test target.
