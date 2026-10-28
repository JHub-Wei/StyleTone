# GoldenSupport — synthetic fixtures and image comparison harness

`GoldenSupport` is the shared, XCTest-free test library for WP-04. Any module
test target in this package already depends on it, so a test file only needs:

```swift
import GoldenSupport
```

It contains:

- deterministic synthetic image generation (10 committed fixtures + ad-hoc specs),
- per-pixel ΔE00 / SSIM / channel-difference reports with thresholds,
- golden-image storage and CI diff artifacts,
- a performance measurement harness and budgets,
- the CI report JSON/Markdown format,
- the authorized-sample manifest types.

It has **no dependency on XCTest**, no network access and no bundled photos, so
it can also be used from a future command-line tool.

## Quick start

```swift
import XCTest
@testable import GoldenSupport

final class MyRenderTests: XCTestCase {
    func testNoOpRenderMatchesInput() throws {
        let input = try FixtureCatalog.fixture(id: "colorchart.macbeth24").render()
        let output = input // replace with the code under test

        let report = try ImageComparator.compare(
            expected: input,
            actual: output,
            thresholds: .identity
        )
        XCTAssertTrue(report.passes, report.summary)
    }
}
```

`report.summary` is a one-line human message; `report.markdown()` is a table
ready for a CI job summary; `report.failures` lists every violated threshold.

## Synthetic fixtures

`FixtureCatalog.fixtures` embeds the ten entries from
`Fixtures/manifest.json`; no bundle resource or repository path is required.

```swift
let fixture = try FixtureCatalog.fixture(id: "face.silhouette")
let pixels: PixelBuffer = try fixture.render()
let asset: ImageAsset = try fixture.imageAsset()
let png: Data = try fixture.pngData()
```

Ad-hoc images can be described without touching the catalog:

```swift
let entry = FixtureManifestEntry(
    id: "tmp.gradient",
    kind: .linearGradient,
    width: 128,
    height: 64,
    colors: ["#000000", "#FFFFFF"],
    axis: .horizontal,
    purpose: "ad-hoc"
)
let buffer = try FixtureRenderer.render(entry)
```

Patterns: `solidColor`, `linearGradient`, `checkerboard`, `colorChart`,
`noise`, `verticalEdge`, `grid`, `faceSilhouette`. The renderer validates the
parameters and throws `GoldenSupportError.invalidFixture` with the entry id.

`FixtureProbes.colorProbes(for:)` returns a handful of `(x, y, colour)`
expectations that both generated pixels and the committed reference PNGs must
satisfy. `FixtureProbes.isMirrorSymmetric(_:)` is useful for the face outline.

## Image comparison

`ImageComparator.compare(expected:actual:thresholds:)` compares two
`PixelBuffer` values (or two `ImageAsset` values) of identical size and returns
an `ImageDifferenceReport`:

| metric | meaning |
|---|---|
| `differingPixelCount` / `differingPixelRatio` | pixels with any RGBA channel delta above `channelTolerance` |
| `meanChannelDelta` | mean absolute RGB delta normalised to `0...1` |
| `maxChannelDelta` | maximum absolute channel delta, `0...255` |
| `meanDeltaE00`, `p95DeltaE00`, `maxDeltaE00` | CIEDE2000 distribution |
| `ssim` | structural similarity on Rec. 709 luma, 8×8 block average |
| `differenceBoundingBox` | bounds of differing pixels, `nil` when identical |
| `failures` | human-readable violated thresholds |
| `passes` | `failures.isEmpty` |

ΔE00 follows Sharma et al. (2005); reference pairs are asserted in
`ColorScienceTests`. SSIM uses the standard constants `C1 = (0.01·255)²` and
`C2 = (0.03·255)²`, population variance and non-overlapping 8×8 blocks
(partial edge blocks included), so values are deterministic across platforms.
ΔE00 costs trigonometric work per pixel: full-image comparison is intended for
test-sized images (a few megapixels at most).

Threshold presets:

| preset | channel tolerance | differing ratio | mean ΔE00 | p95 ΔE00 | max ΔE00 | min SSIM |
|---|---|---|---|---|---|---|
| `.identity` | 0 | 0 | 0.05 | 0.1 | 0.25 | 0.9999 |
| `.strict` | 1 | 0.2% | 1.0 | 2.0 | 6.0 | 0.99 |
| `.standard` | 2 | 1% | 2.0 | 5.0 | 12.0 | 0.95 |
| `.structural` | 8 | 10% | 4.0 | 10.0 | 30.0 | 0.85 |

Use `.identity` for “no-op must be byte-exact”, `.structural` for
structure-preserving warps, and a custom `ImageThresholds` when a module owns
its own budget. Do not relax thresholds to make a failing test pass; document
the change next to the budget.

Other helpers:

```swift
let map: [Float] = try ImageComparator.deltaEMap(expected: a, actual: b)
let diff: PixelBuffer = try ImageComparator.differenceImage(expected: a, actual: b, amplification: 8)
let ssim: Double = ImageComparator.structuralSimilarity(a, b)
```

## Golden images and artifacts

`GoldenImageStore` reads/writes `<name>.png` under a directory of your choice
(use `TestShared.TemporaryDirectory` for tests):

```swift
let store = GoldenImageStore(directory: directory)
let report = try store.compare(actualBuffer, named: "warp.noop", thresholds: .identity)
```

Recording is explicit: `GoldenImageStore(recordMode: true)` or
`GOLDEN_RECORD=1`. A recording run saves the golden and returns a passing
identity report; never enable it in CI. Golden names are validated and cannot
escape the store directory.

`DiffArtifactWriter.write(expected:actual:report:name:to:)` writes:

```text
<name>-expected.png
<name>-actual.png
<name>-difference.png   # amplified grayscale absolute difference
<name>-report.json      # ImageDifferenceReport
<name>-report.md
```

## Performance template

`PerformanceHarness` records monotonic `ContinuousClock` samples with warm-up
iterations; it does not assert. Compare `p95Seconds` with a budget in your test:

```swift
func testExportBudget() throws {
    let measurement = try PerformanceHarness.measure(
        name: "export.12MP",
        iterations: 5,
        warmupIterations: 2
    ) {
        _ = try renderExport()
    }
    let verdict = PerformanceBudget.export12MP.verdict(for: measurement)
    XCTAssertTrue(verdict.passed, verdict.message)
}
```

Budgets mirror contracts §10 (first frame 1.5 s, pose warp 1/30 s, slider
response 100 ms, 5-pair learning 90 s, 12 MP export 6 s) with a 10% default
allowance for CI noise. CI checks regressions only; it never asserts absolute
device performance. Async work uses `measureAsync`. Reports carry `p50`, `p95`,
`min`, `max` and `mean`.

## CI report format

`GoldenReport` is the machine-readable artifact:

```swift
var report = GoldenReport(suite: "StyleToneGeometryTests")
report.append(.comparison(name: "warp.noop", report: comparisonReport))
report.append(.performance(name: "warp.1080p", measurement: measurement, verdict: verdict))
report.append(.fixture(name: "fixture-self-check", passed: true))

let artifacts = try report.write(to: artifactsDirectory)
// artifacts.jsonURL, artifacts.markdownURL
```

`report.json` schema (also in `Schema/golden-report.schema.json`):

```json
{
  "schemaVersion": 1,
  "tool": "GoldenSupport",
  "toolVersion": "1.0.0",
  "suite": "StyleToneGeometryTests",
  "generatedAt": "2026-10-24T12:00:00Z",
  "environment": {
    "isCI": true,
    "provider": "github-actions",
    "runID": "1234567890",
    "runnerOS": "macOS",
    "osVersion": "Version 15.0"
  },
  "entries": [
    {
      "kind": "imageComparison",
      "name": "warp.noop",
      "status": "passed",
      "message": "PASS 192x144 differing=0 …",
      "metrics": { "ssim": 1, "meanDeltaE00": 0 },
      "thresholdFailures": []
    }
  ],
  "summary": { "total": 1, "passed": 1, "failed": 0, "skipped": 0 }
}
```

`kind` is one of `imageComparison`, `performance`, `fixtureSelfCheck`,
`custom`; `status` is `passed`, `failed` or `skipped`. The summary is derived
from `entries` when decoding, JSON uses sorted keys and the document is
versioned with `schemaVersion`. Environment metadata comes from the standard
`CI`, `GITHUB_ACTIONS`, `GITHUB_RUN_ID` and `RUNNER_OS` variables — no user
data.

## Tests

```bash
# Fast target
swift test --filter GoldenSupportTests

# Whole package (what CI runs)
swift test
```

`FixtureSelfCheckTests` is the WP-04 acceptance suite. It verifies:

1. `Fixtures/manifest.json` decodes, validates and equals the embedded catalog.
2. All ten fixtures regenerate byte-identically.
3. Every reference PNG exists, keeps its declared SHA-256 and satisfies the
   colour probes; the Swift renderer agrees with the committed reference within
   a tight colour/layout tolerance (byte equality for flat fixtures, structural
   tolerance for the outline).
4. The face outline is mirror-symmetric and structurally matches its reference.
5. The reference directory contains exactly the declared files.
6. `Fixtures/samples/manifest.json` is valid and no photo files are committed.

These tests locate the repository by walking up from the test source; set
`ST_REPO_ROOT` when the bundle runs elsewhere.

## Golden portrait corpus (WP-25)

`GoldenSupport` also owns the synthetic portrait corpus used by
`Tests/Integration`:

- `PortraitCorpus` / `PortraitSampleSpec` — the 100-sample metadata document
  (`Tests/Integration/Corpus/portrait-corpus.json`) and coverage counts.
- `PortraitRenderer` — deterministic cartoon studio portraits with person, skin
  and background-structure masks, face landmarks, body joints and straight-line
  ground truth. No photograph is read.
- `PortraitMetricEvaluator` — ΔE00 on skin, sampled full-image ΔE00, SSIM,
  background-line bend, skin-tone safety/fairness and silhouette metrics.
- `PortraitImageSignature` — compact 16×16 luma / 8×8 chroma fingerprint used by
  the committed baseline.
- `PortraitBaseline` / `PortraitBaselineComparator` — per-metric regression
  tolerances with human-readable failure messages.
- `PortraitRegressionReport` / `PortraitArtifactBuilder` — CI report, contact
  sheet and four-quadrant diagnostics image.

```swift
let scene = try PortraitRenderer.render(sample)
let evaluation = try PortraitMetricEvaluator.evaluate(
    scene: scene,
    source: scene.pixels,
    retouched: retouched,
    output: output
)
XCTAssertTrue(evaluation.isPassing, evaluation.failures.joined(separator: "; "))
```

See `Tests/Integration/README.md` for the metrics, thresholds, gates, baseline
recording flow and CI artifact layout.

## Limitations and intentionally omitted features

- No perceptual hash, no GPU comparison and no streaming comparison for huge
  images; reports are computed in memory.
- SSIM is a deterministic block average, not the exact Wang et al. Gaussian
  implementation; thresholds are calibrated for regression detection.
- Reference PNGs are produced by a Python/Pillow generator. If Pillow’s PNG
  encoder changes, regenerate and update the hashes; the pixel content is
  stable.
- No XCTest import: assertion helpers return reports so the harness also works
  outside XCTest. Tests keep `XCTAssert` in their own target.
