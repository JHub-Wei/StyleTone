# StyleToneGeometry Face (WP-12)

Face slim/jaw displacement contributions for the mesh-warp engine. The code
lives in `Sources/StyleToneGeometry/Face/` and implements the frozen
`GeometryPass` contract from `contracts.md` §4.1. It contains no background
protection (WP-15), no body/leg logic (WP-13/14) and no UI.

## Entry points

```swift
// GeometryPass for the engine / editor:
let pass = FaceWarpContributor()

// Diagnostics (warnings + per-face metrics) for the editor warning strip:
let plan = try pass.plan(
    for: analysis,
    parameters: geometry.face,
    gridDimension: 32
)
print(plan.warnings)

let engine = GeometryRenderingEngine(
    passes: [GeometryPassEntry(phase: .face, pass: pass)],
    backgroundConstraint: nil,          // WP-15
    configuration: .preview
)
```

`FaceWarpPlan` is a pure value: it can be inspected in tests, applied to a
`WarpField`, or discarded. The engine calls `FaceWarpContributor.contribute`,
which plans for the field's current density (32×32 preview / 64×64 export) and
adds the offsets in place.

## Displacement strategy

### Face metrics

For every face the pass derives a symmetric geometry from landmarks:

- **Symmetry axis** `centerX`: midpoint of the two eye centres (pupils are the
  fallback). Both eyes are required; the pass never guesses a face axis from a
  bounding box alone.
- **Eye line** `eyeY`: midpoint of the eye centres. No displacement is applied
  on or above this line, which protects the forehead and hairline.
- **Chin line** `chinY`: lowest face-contour point, clamped between the eye line
  plus 20 % of the bounding-box height and the bounding-box bottom. If no
  contour is available the bounding box supplies the fallback and
  `.missingFaceContour` is reported.
- **Face width**: bounding-box width, extended to the 90th percentile of contour
  distance when the contour is wider. The profile is normalized by this width,
  so the same slider value behaves consistently across face sizes.

The displacement profile depends only on `|x - centerX|` and the vertical
coordinate between `eyeY` and `chinY`. Feature guards are mirrored around
`centerX`, so the field is exactly mirror-symmetric even when the detected
landmarks are not.

### Bands and envelopes

Both parameters move content **towards the symmetry axis** (left side moves
right, right side moves left); `+x` offsets move content right, `+y` moves it
down. There is no vertical jaw lift in this WP, so the contribution cannot
distort the mouth/teeth vertically.

| Envelope | Shape |
|---|---|
| Lateral | 0 on the centre line, smoothstep up over `q = 0.22...0.62`, full over the cheek, fades to 0 at `q ≈ 1.22` (`q = |x - cx| / halfWidth`) |
| Top (hairline) | 0 at/above the eye line, smoothstep in over `t = 0.02...0.20` |
| Bottom | full at the chin, fades to 0 over `t = 1.02...1.24` |
| `slim` band | rises `t = 0.08...0.30`, falls `t = 0.80...1.05` (cheek/mid-face) |
| `jaw` band | rises `t = 0.42...0.70`, falls `t = 1.05...1.24` (jaw line/chin) |

`t = (y - eyeY) / (chinY - eyeY)`.

### Protection

- Eyes, eyebrows, nose, outer lips and inner lips (teeth) each get an
  axis-aligned guard expanded by a feature-relative margin plus a grid-aware
  minimum: the planner raises `featureProtectionMargin` (default 0.02) to at
  least one full mesh cell (`1.05 / (gridDimension - 1)`).
- Inside a guard the displacement is **exactly zero**; outside it ramps back
  over `featureProtectionFeather` (0.02).
- The grid-aware margin makes every vertex of the cell around a feature part of
  the hard-zero core, so bilinear sampling at the feature point is zero even at
  full strength. Protection is intentionally stronger at 32×32 preview (~0.034)
  than at 64×64 export (~0.017), where more vertices fit around a feature.
- The hairline is protected by the top envelope (zero at/above the eye line) and
  by the eyebrow guards.
- Ears are handled by the lateral fade; there is no separate ear landmark guard.

### Strength limits

All values are fractions of the face width (`2 * halfWidth`):

- `slimDisplacementFraction = 0.045` peak inward displacement at `slim = 1`
- `jawDisplacementFraction = 0.035` peak inward displacement at `jaw = 1`
- `maximumCombinedDisplacementFraction = 0.065` cap for slim + jaw
- `maximumAbsoluteDisplacement = 0.04` normalized image units (absolute cap)

Slider values are clamped to `0...1`. The cap is applied before the spatial
envelope, so overlapping faces cannot exceed it after blending.

### Multiple faces

- Faces are filtered by confidence (`>= 0.35`) and bounding-box area
  (`>= 0.0025` of the frame), then sorted by **descending area**.
- At most `maximumFaceCount = 4` faces are processed; the largest faces are
  kept and `.faceCountLimited` is reported.
- Each face is slimmed independently with the same requested strength.
- If two face supports share a vertex, the contributions are blended by their
  combined coverage instead of being summed, so no vertex receives double
  strength.

### Warnings and failures

`GeometryPass.contribute` has no warning return value. The pass is a safe no-op
for unusable faces and never throws for missing faces/landmarks. Callers that
need user-visible diagnostics use `plan(...)`:

| Warning | Meaning |
|---|---|
| `.noFace` | no face in the analysis |
| `.noUsableFace` | faces existed but none produced a contribution |
| `.multipleFaces(count:)` | more than one face detected; all usable faces processed by area |
| `.faceCountLimited(detected:processed:)` | count cap reached |
| `.lowConfidence(faceIndex:confidence:)` | face skipped by confidence filter |
| `.faceTooSmall(faceIndex:areaFraction:)` | face skipped by area filter |
| `.insufficientLandmarks(faceIndex:)` | no eye pair, or no nose/lips to protect |
| `.missingFaceContour(faceIndex:)` | bounding-box fallback used for width/chin |
| `.degenerateFace(faceIndex:)` | non-finite or degenerate geometry; face skipped |

No warning contains an image path, face identifier or other PII.

## Tests

```bash
swift test --filter StyleToneGeometryTests
# WP-12 only:
swift test --filter FaceWarpContributorTests
swift test --filter FaceWarpPerformanceTests
```

Coverage:

- synthetic contour/eye/nose/lip landmarks; cheek displacement direction and
  left/right symmetry;
- exact zero at every protected feature point and at the hairline/forehead;
- slim vs jaw vertical bands;
- monotonic strength and both caps (including `slim = jaw = 1`);
- asymmetric contour still yields a symmetric field;
- multiple faces sorted by area, count cap, blend;
- low confidence, tiny faces, missing eyes/lower landmarks, missing contour;
- plan density mismatch leaves the field untouched;
- `GeometryPipeline` border pinning + `GeometryRenderingEngine` identity and
  actual CPU warp without black edges;
- 32×32 contribution p95 against the 30 fps frame budget, plus a 64×64 export
  measurement.

The performance test prints `FACE_GEOMETRY_PERF ...` lines for CI logs.
Measured baseline on macOS CI (debug, 2026-10-24): 3-face contribution p95
**1.0 ms at 32×32** (1024 fps) and **3.4 ms at 64×64** (295 fps). See
[PERFORMANCE.md](PERFORMANCE.md) for method and caveats.

CI: run [40112796982](https://github.com/JHub-Wei/StyleTone/actions/runs/40112796982)
completed successfully; 579 tests (4 skipped) with 0 failures.

## Limitations / follow-ups

- No background straight-line protection; that is WP-15's constraint and runs
  after this pass.
- No occlusion/person-mask attenuation. A hand covering the jaw is deformed
  with the face; WP-13/15 can add masks later.
- No jaw lift (vertical component) and no chin-length change in v1; the two
  sliders only narrow horizontally.
- Profile faces without a usable eye pair are skipped rather than guessed.
- Preview (32×32) and export (64×64) share the same geometry and fixed
  protection margins; only rasterization density differs.
- A 64×64 export is one shot, so the contribution is measured separately from
  the interactive 30 fps budget.
