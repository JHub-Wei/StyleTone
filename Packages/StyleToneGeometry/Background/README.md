# StyleToneGeometry Background (WP-15)

Background protection for the mesh-warp engine. The code lives in
`Sources/StyleToneGeometry/Background/` and implements the frozen
`GeometryConstraint` contract from `contracts.md` §4.1. It contains no face,
body or leg shaping logic (WP-12/13/14), no UI and no changes to
`StyleToneGeometry/Core`.

The constraint keeps straight background structure straight (door frames,
floor tile seams, table edges, window mouldings, text baselines) and preserves
the face/body/leg slimming effect inside the subject region.

## Entry points

```swift
// Register once in the engine; the engine runs it last, only when
// GeometryParameters.backgroundProtection is true.
let engine = GeometryRenderingEngine(
    passes: [
        GeometryPassEntry(phase: .face, pass: FaceWarpContributor()),
        GeometryPassEntry(phase: .body, pass: BodyWarpContributor()),
        GeometryPassEntry(phase: .legs, pass: LegsWarpContributor())
    ],
    backgroundConstraint: BackgroundWarpConstraint(),
    configuration: .preview
)

// Diagnostics: warnings, detected lines/rectangles and metrics.
let field = try engine.makeField(analysis: analysis, geometry: parameters)
let plan = try BackgroundWarpConstraint().makePlan(field: field, analysis: analysis)
print(plan.warnings)
print(plan.metrics.maximumLineDeviationBefore, plan.metrics.maximumLineDeviationAfter)

// Toggle-off warning for the editor. The engine skips the constraint when the
// switch is off, so the editor asks for a risk assessment explicitly.
let risk = try BackgroundWarpConstraint().assessRisk(
    field: field,
    analysis: analysis,
    protectionEnabled: false
)
if risk.level != .low {
    showBackgroundWarning(risk.warnings)
}
```

`BackgroundParameters`/`backgroundProtection` stay in WP-06. This module only
reads `PortraitAnalysis` (WP-05) and rewrites a `WarpField`.

## Inputs

| Input | Use |
|---|---|
| `backgroundEdgeMask` | Edge evidence from WP-05 (Sobel + long run mask, person-suppressed). Required for line/rectangle detection. |
| `personMask` | Subject support. Full displacement inside the person, feathered damping outside. |
| `faces` / `body` | Fallback subject support when the person mask is missing or empty. |
| `imageSize` | Aspect ratio for isotropic feathers and for mask-size consistency warnings. |

No image pixels are read and no image I/O is performed; the WP-05 mask is the
analysis-time edge detector, and WP-15 consolidates it into lines, rectangles
and protection weights.

## Detection strategy

1. **Mask sampling.** The full-resolution edge mask is sampled onto a structure
   grid `2 ×` the warp grid (clamped to 48...128). Both the **peak** and the
   **mean** coverage of each bin are kept. Peak preserves thin lines; mean
   separates a line from dense texture. Masks up to 2 MP are read every pixel
   (exact unit tests); larger masks use a stride chosen from
   `maskSamplingStride`/`maximumMaskSamples`.
2. **Edge evidence.** `evidence = clamp(max(peak × 0.9, mean × 2.4))`. A
   line-like edge therefore reaches high evidence while a weakly textured area
   stays low.
3. **Line runs.** Cells above `structureThreshold` form horizontal and vertical
   runs. A run is accepted only if it is long enough
   (`minimumLineSpanFraction`, default 15 % of the frame) **and** it is a thin
   ridge: its mean evidence must exceed the mean of the two parallel neighbour
   rows/columns by `ridgeContrast`, unless the neighbours are clean background
   (`≤ 0.20`). Dense texture is high everywhere and is rejected.
4. **Merging.** Adjacent rows/columns with overlapping runs are merged into one
   line with a strength-weighted position, so a 2-cell-thick frame edge does not
   become two lines. Lines are ranked by span × strength and capped at
   `maximumLineCount`.
5. **Rectangles.** Consecutive horizontal and vertical lines whose extents cover
   the candidate box are closed into axis-aligned rectangles (floor tiles, door
   panels, window panes). Rectangles larger than
   `maximumRectangleFillAreaFraction` only contribute boundary protection.
6. **Limits.** More lines/rectangles than the cap produces
   `.lineDetectionLimited` / `.rectangleDetectionLimited`.

Curved and diagonal edges are not reported as lines (they fail the run test) but
still receive generic edge protection from their evidence.

## Protection strategy

### Subject support

Subject support is `1` inside the person and falls to `0` outside a smooth
person-mask gate. When the person mask is missing or covers less than
`subjectMaskEmptyCoverage` of the frame, a face/body fallback is used:

- every face box is expanded by `faceSupportExpansion` (default 25 % of the box
  size), which covers the face pass envelope (1.22 × half-width) with margin;
- the body-joint bounding box is expanded by `bodySupportMargin`;
- support is `max(person mask, fallback)`, so a partial segmentation cannot
  accidentally weaken face or body slimming.

### Retention

The constrained offset is the source offset multiplied by independent retention
factors. A factor of `1` keeps the displacement; `0` pins it.

| Region | Factor | Default |
|---|---|---|
| Subject support (`support = 1`) | `1` | 1.00 |
| Generic background | `backgroundRetention` | 0.60 |
| Generic edge (text, curved architecture) | `edgeRetention` | 0.35 |
| Straight line core | `lineRetention` | 0.05 |
| Rectangle interior | `rectangleRetention` | 0.55 |

Inside the subject the factor is exactly `1`: face/body/leg slimming is not
weakened. A background-only baseline keeps 60 % of the motion so the person
silhouette does not tear; this is intentional and is measured by
`BackgroundProtectionMetrics/backgroundRetention`.

### Rigid lines

Damping alone would still let a line bend because different vertices would be
damped differently. The rigid-line step computes, for every detected line, the
weighted mean source displacement of its core and replaces each core vertex with
that single displacement (multiplied by `lineRetention`). A 20 px line at a
frame edge therefore moves at most ~1 px but cannot become crooked. Blending
with the damped field uses `lineRigidity` and the line falloff.

### Falloff

Line protection is full within `lineCoreRadius` and falls off with smoothstep
over `lineFeather`. Rectangle fill ramps in over `rectangleFillRamp` from the
boundary. Generic edge evidence is spread one cell onto its 4-neighbours
(`edgeSpreadWeight`) to avoid a one-vertex damping spike.

## Warnings and risk

`GeometryConstraint` has no warning return channel. Use `makePlan` or
`assessRisk`:

| Warning | Meaning |
|---|---|
| `edgeMaskUnavailable` | No WP-05 structure mask; only generic background damping runs. |
| `edgeMaskEmpty` | Mask present but no pixel above `minimumEdgeValue`. |
| `noStructureDetected` | Edges exist but no line/rectangle formed; curved edges are still damped. |
| `maskSizeMismatch` | Edge mask dimensions differ from `imageSize` (normalized geometry still works). |
| `subjectMaskUnavailable` / `subjectMaskEmpty` | Face/body boxes supplied subject support. |
| `subjectRegionUnavailable` | No subject at all; the whole frame is background. |
| `lineDetectionLimited` / `rectangleDetectionLimited` | Detection cap reached. |
| `protectionDisabled` | Switch-off advisory from `assessRisk`. |
| `protectionDisabledWithStructures` | Switch is off and structure would visibly move. |
| `structureDisplacementResidual` | Protection ran, but a structure core still moves. |

Risk levels (`low` / `moderate` / `high`) are derived from the number of
structure-core vertices above `riskDisplacementThreshold` and the largest such
displacement. `moderate` is a "worth mentioning" banner; `high` is "clearly
visible".

## Metrics

`BackgroundProtectionMetrics` exposes the acceptance numbers directly:

- `maximumLineDeviationBefore/After` — largest normal deviation of the
  interpolated field along a detected line, sampled in the visible background
  part only. It is the "line is crooked" metric.
- `maximumStructureDisplacementBefore/After` — largest displacement on a
  structure core (`protection ≥ 0.75`).
- `subjectRetention` — displacement ratio inside the subject; `1` means no
  weakening.
- `backgroundRetention` — displacement ratio in the background.
- `protectedBackgroundVertexFraction`, `meanStructureProtection`,
  `riskyVertexCount`, `residualRiskyVertexCount`.

## Acceptance

- Automated 100-case synthetic proxy: `0 %` obvious distortion, subject
  retention `1.0`; see `ACCEPTANCE.md`.
- Manual review of 100 authorized real photos is **pending** because the
  repository intentionally contains no real photos. The review protocol and
  sign-off template are in `ACCEPTANCE.md`.
- Performance method and CI baseline: `PERFORMANCE.md`.

## Tests

```bash
swift test --filter BackgroundStructureDetectorTests
swift test --filter BackgroundWarpConstraintTests
swift test --filter BackgroundProtectionAcceptanceTests
swift test --filter BackgroundProtectionPerformanceTests
# Strict debug-build performance budget:
ST_BACKGROUND_PERF_STRICT=1 swift test --filter BackgroundProtectionPerformanceTests
```

## Scope and risks

- Only `Sources/StyleToneGeometry/Background/`, the module test subdirectory and
  this documentation are touched. `Core`, `Face`, `Body`, `Legs`, `StyleToneUI`
  and `StyleToneVision` are unchanged.
- The detector handles **axis-aligned** man-made structure. Diagonals and curves
  rely on generic edge damping; a strongly bent horizon line (no long
  horizontal run in the mask) is only partially protected.
- The edge mask is produced at the analyzer's proxy resolution and upsampled;
  very thin, low-contrast lines may be missing from the mask. Falloff and
  baseline damping still reduce visible warping, but no line can be pinned if it
  is not in the mask.
- The rigid-line target is the mean displacement over the visible line. A line
  that is only a few pixels behind a cheek may translate slightly rather than
  stay perfectly fixed; this is bounded by `lineRetention`.
- Detection is deterministic for a given analysis and configuration. The
  constraint caches nothing: each frame re-samples the masks. See
  `PERFORMANCE.md` for the measured cost.
