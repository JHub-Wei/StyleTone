# StyleToneVision

WP-05 portrait analysis and pair-quality assessment. The module wraps Vision,
converts its output into the frozen `StyleToneCore` contracts, and never
identifies people or retains face templates.

## Public API

```swift
import StyleToneVision

let analyzer = VisionPortraitAnalyzer()
let analysis: PortraitAnalysis = try await analyzer.analyze(image)

let detailed = try await analyzer.analyzeDetailed(image)
print(detailed.confidence)          // aggregate 0...1
print(detailed.diagnostics.duration)
```

`VisionPortraitAnalyzer` conforms to `PortraitAnalyzing`. Use
`analyzeDetailed(_:)` when a caller needs aggregate confidence or diagnostics;
the protocol entry point stays `analyze(_:)`.

```swift
let pairAnalyzer = VisionPairQualityAnalyzer()
let quality: PairQuality = try await pairAnalyzer.assess(original: a, edited: b)
let detailedPair = try await pairAnalyzer.assessDetailed(original: a, edited: b)
print(detailedPair.metrics.semanticSimilarity as Any)
```

`VisionPairQualityAnalyzer` conforms to `PairQualityAnalyzing`. Reasons are
localization keys (`pair.reason.*`), never prose.

### Configuration

Both analyzers accept a value configuration:

- `VisionAnalysisConfiguration`: proxy size (default 1024), face/body
  confidence floors, segmentation quality, mask toggles, low-light threshold.
- `VisionPairQualityConfiguration`: resolution/aspect thresholds, similarity
  thresholds, misalignment and structural-delta bands.

Defaults match the contracts' 1024 px proxy and 1.5 s first-frame budget.

## Coordinate convention

Vision emits normalized points and rectangles with a **bottom-left** origin.
`PortraitAnalysis` uses **top-left** origin (`y` grows downwards), matching
`NormalizedPoint.isNormalized` and the shared test mocks. Every coordinate goes
through `VisionCoordinateMapper`; converted points are clamped to `0...1`.

## Masks

All three masks use `MaskBuffer` (8-bit alpha, row-major) and have exactly the
input image's `PixelSize`:

| Mask | Source | Notes |
|---|---|---|
| `personMask` | `VNGeneratePersonSegmentationRequest` | `nil` below minimum coverage |
| `skinMask` | per-face ellipse + adaptive YCbCr | excludes eyes, eyebrows, lips |
| `backgroundEdgeMask` | adaptive Sobel + straight-line runs | suppresses person-mask pixels |

Detection runs on the proxy; masks are bilinearly resampled back to the
original size. No mask contains identity information.

## Degradation

- No face: `personMask`/`backgroundEdgeMask` may still be present; `skinMask`
  is `nil`; warnings include `.noFace`.
- Multiple faces: all faces are returned (largest first, capped), warning
  `.multipleFaces`; skin regions are united.
- No body or too few joints: `body == nil`, warning `.noBody`.
- Detector error: the stage is recorded in `diagnostics.failedStages` and the
  result degrades instead of throwing. Only an unusable image throws.
- Low light / low confidence / border-clipped face / missing landmarks:
  warnings `.lowLight`, `.lowConfidence`, `.occlusion`.

## Private by construction

- No network imports or requests; no photo upload.
- No face recognition, face templates or identity classification request.
- No `print`, `os_log` or file-name logging in the module.
- Feature prints exist only in transient memory during one assessment.
- `PrivacySourceAuditTests` fails if a forbidden token (`URLSession`,
  `VNClassifyImageRequest`, logging calls) enters the module.

## Performance

The analyzer detaches Vision work from the caller's actor and checks
`Task.cancellation` between stages. Background-structure analysis runs on at
most a 512 px working buffer and resamples its mask to the proxy size.

The debug XCTest suite runs a broad 1024×768 envelope to catch regressions.
The contractual p95 ≤ 1.5 s budget is opt-in because a debug XCTest process is
not a Release device measurement:

```bash
ST_RUN_VISION_1024_PERF=1 swift test -c release \
  --filter VisionPortraitAnalyzerTests/testAnalysisOf1024ProxyMeetsDeviceBudget
```

macOS CI is the authoritative build runner; Windows sessions cannot execute
Vision.

## Authorized-sample spot check

The repository never contains real photos. For the 20-sample manual audit:

1. Put photos in `Fixtures/samples/` (git-ignored) and add manifest entries
   with license/authorization metadata (see `Fixtures/README.md`).
2. Run:
   ```bash
   ST_RUN_AUTHORIZED_SAMPLE_AUDIT=1 swift test \
     --filter AuthorizedSampleAuditTests
   ```
3. Open the `authorized-sample-audit.json` attachment and check each photo for:
   - face count and landmark placement (eyes, nose, lips, contour);
   - body joints (shoulders, hips, knees, ankles) on full-body samples;
   - person/skin/background masks against the image;
   - warning correctness (backlit, cropped, group photo);
   - 1024 px analysis duration ≤ 1.5 s.
4. Record failures as fixture/manifest issues, never by committing the photo.

## Tests

```bash
swift test --filter StyleToneVisionTests
```

Coverage includes coordinate conversion, multi-face/no-face/no-body warnings,
mask sizing/resampling, skin exclusion of eyes/lips, straight-line background
masks, classifier grading, pair-quality integration (identical, unrelated,
low-resolution, wrong aspect, translated) and the privacy source audit.

## Limitations

- Registration is translation-only. Rotation and scale changes are caught by
  aspect/resolution checks and the structural delta, not by a full affine solve.
- Skin probability is a heuristic chroma/luma model, not a learned matte. It is
  intentionally conservative (neutral grey is rejected).
- Background line detection covers long horizontal/vertical runs; diagonal
  structures rely on the raw gradient term.
- Feature-print distance is mapped to a ranking score, not a calibrated
  probability.
