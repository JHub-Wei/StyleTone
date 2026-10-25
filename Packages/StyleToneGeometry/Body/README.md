# Body shaping (WP-13)

Arm and waist contour inset as a `GeometryPass` contribution. The source lives
in `Sources/StyleToneGeometry/Body/`; this directory holds the design notes.

## Integration

```swift
let bodyPass = BodyWarpContributor()
let pipeline = GeometryPipeline(
    passes: [GeometryPassEntry(phase: .body, pass: bodyPass)],
    configuration: .preview
)

// Warnings are available without mutating a field.
let plan = try bodyPass.makePlan(
    analysis: analysis,
    parameters: geometry,
    gridWidth: 32,
    gridHeight: 32
)
let field = try pipeline.makeField(
    analysis: analysis,
    parameters: geometry
)
```

`BodyWarpContributor.contribute` adds to the existing field, never resizes it, and
does not apply boundary pinning. WP-06's `GeometryBoundaryPolicy` still runs
after the pass.

## Strategy

- **Frame:** shoulder-centre → hip-centre axis. Waist height is a fraction of
  this axis, not a pixel/centimetre measurement.
- **Arms:** each shoulder-elbow-wrist polyline gets a capsule-shaped pinch
  toward its own axis. Influence fades in after the shoulder, fades out before
  the wrist (hands are untouched), and is suppressed over the torso envelope.
- **Waist:** the torso half-width is measured from the person mask along the
  perpendicular at three heights. A Gaussian band around the waist compresses
  the contour toward the torso axis; a common half-width keeps the result
  symmetric and avoids dragging one side from an adjacent arm.
- **Torso/arm separation:** arm influence is blocked inside the interpolated
  torso envelope; waist influence is blocked near available arm capsules.
  This protects clothing/torso interior from double warping as far as pose and
  segmentation allow.
- **Background:** every displacement is gated by the person mask. Background
  straight-line protection is deliberately **not** implemented here; WP-15's
  `GeometryConstraint` runs afterwards.
- **Bounds:** per-arm, per-waist and combined per-vertex caps are expressed in
  short-side image units. The planner additionally caps a vertex at 42 % of its
  distance to the deformation axis so contours cannot cross the centreline.
- **No identity/biometrics:** only normalized joints, mask alpha and
  image-relative ratios are used. Nothing is persisted or logged.

## Safety and warnings

`BodyWarpPlan.warnings` is the UI-facing diagnostic surface because the frozen
`GeometryPass` protocol has no warning return value.

| Situation | Behavior |
|---|---|
| no body observation | no-op, `.noBody` |
| no person mask | no-op, `.noSegmentation` |
| analysis reports occlusion | no-op, `.occlusion` |
| body confidence below threshold | no-op, `.lowConfidence` |
| body confidence below full strength | attenuated + `.lowConfidence` |
| analysis reports low confidence | further attenuation + `.lowConfidence` |
| multiple faces / multiple mask blobs | no-op, `.multiplePeople` (default) |
| `multiplePersonPolicy == .primaryBody` | shapes primary at reduced strength + `.multiplePeople` |
| missing arm joints | other arm/waist still run + `.incompletePose` |
| degenerate limb/torso | affected region skipped + `.degeneratePose` |
| insufficient mask coverage / blank mask | affected region skipped + `.occlusion` |
| no usable contour width | `.weakSegmentation` |
| combined cap reached | `.strengthLimited` |

`PortraitAnalysis` exposes one primary body and the segmentation mask is not
person-specific. Multi-person support is therefore a safety policy, not
per-person shaping. `.skip` is the default; `.primaryBody` is opt-in and should
only be used when the caller accepts leakage onto a second silhouette.

## Tests

```bash
swift test --filter BodyWarpContributorTests
swift test --filter BodyWarpPerformanceTests
```

Synthetic tests build a 160×240 single-person silhouette with a 1000×1500
analysis frame. They cover no-body/no-mask/occlusion skip, symmetric waist and
both arms, hand/background immobility, strength monotonicity and hard caps,
low-confidence attenuation, multi-person and multi-face warnings, missing-arm
degradation, field addition, and a 32×32 preview performance envelope.

`BodyWarpPerformanceTests` measures 32×32 planning + contribution with the shared
`GeometryPerformanceProbe` and asserts p95 is below the 33.3 ms preview frame
budget. Planning is `O(grid² × arm segments + torso scans + probe²)` and uses no
image-pixel processing. The test prints the `GEOMETRY_PERF`-style summary in CI;
absolute device numbers must be recorded on the macOS runner.

## Known limitations / risks

- Clothing is not segmented. The pass keeps shaping inside the person mask and
  limits/taper the displacement, but a garment edge can still move with the
  body; WP-15 cannot protect arbitrary cloth.
- A loose arm resting against the torso may have its inner contour suppressed
  by the torso envelope, producing a one-sided (outer contour) inset.
- The multi-person detector is a coarse connected-component heuristic plus face
  count. Two people touching, or a very small second person, can be missed.
- The person mask gate is sampled at mesh vertices and then interpolated by the
  renderer. A background line immediately adjacent to a silhouette can still
  receive a small interpolated displacement; WP-15 remains the backstop.
- Wrist taper protects the hand silhouette but not jewelry/props below the
  wrist that the segmenter merges into the person.
