# StyleToneGeometry Legs (WP-14)

Leg slim and 1.00–1.15× leg lengthening as a WP-06 `GeometryPass`.

- Implementation: `Sources/StyleToneGeometry/Legs/`
- Tests: `Tests/StyleToneGeometryTests/Legs/`
- Contract: `contracts.md` §4.1 (`GeometryPass`, `WarpField`, Face → Body → Legs
  → constraints → boundary policy)
- Owner: WP-14. This pass does not modify `Core/`, `Face/`, `Body/`,
  `Background/` or UI.

## Integration

```swift
let engine = GeometryRenderingEngine(
    passes: [
        GeometryPassEntry(phase: .face, pass: FaceWarpContributor()),
        GeometryPassEntry(phase: .body, pass: BodyWarpContributor()),
        GeometryPassEntry(phase: .legs, pass: LegsWarpContributor())
    ],
    backgroundConstraint: BackgroundWarpConstraint(), // WP-15
    configuration: .preview
)
```

The pass reads `PortraitAnalysis.body` and `GeometryParameters.body`:

| Parameter | Meaning | Effect |
|---|---|---|
| `body.leg` | `0...1` | inward contour slimming |
| `body.legLength` | `1.00...1.15` | vertical leg lengthening |

`PortraitAnalysis.personMask` is used when its pixel size matches
`imageSize`; otherwise the pass falls back to a pose-derived leg width and emits
`.noPersonMask`. The pass never requires a face, but every detected face
bounding box is a hard-zero guard for lengthening.

## Anchors and displacement

For each leg the planner builds a two-segment centreline **hip → knee → ankle**
and validates that it is vertical, non-crossing and inside the frame.

### Lengthening

The **higher of the two ankles is the fixed anchor**: content at and below it has
exactly zero displacement, so both feet and shoes cannot be stretched, compressed
or cropped by the lengthening field when the pose is slightly asymmetric. Let

```
L  = anchorAnkle.y - meanHip.y
s  = effective body.legLength (1.00...1.15)
d  = (s - 1) * L                      // hip content shift, capped
q  = (ankle.y - y) / L                // output coordinate, 0 at ankle
m  = maximum upward field offset      // content at y samples from y + m
```

For `q <= s` the non-linear mapping is

```
m(q) = L * (q - (q/s + gamma * q * (s - q)))
gamma = nonlinearity * (1 - 1/s) / s
```

so the hip content moves by `d`, the knee by a smaller amount, and the calf
moves least. The local vertical stretch is monotonic and bounded (≈1.21 at
`s = 1.15` with the default `nonlinearity = 0.35`). Above the shifted hip,
`m` fades to zero over `torsoBlendHeight` with a cubic Hermite; the waist
absorbs the hip shift instead of leaving a hard seam. Face bounds are excluded
from that blend.

The knee and hip are therefore *control anchors*: the ankle is fixed, the knee
and hip move upward by the segment-proportional amounts. The effective scale is
capped by both `1.15` and `maximumVerticalDisplacement`; when the cap binds the
plan reports `.strengthLimited` and a smaller `effectiveLegLength`.

### Slimming

Each leg has a compact lateral bump

```
bell(u) = u * exp(0.5 * (1 - u^2)),        u = |x - centreX| / halfWidth
```

for `u <= 1`, then a smooth fade over `lateralFeather * halfWidth`. The bump is
zero on the centreline, peaks on the estimated contour and has zero derivative
at the peak. The inward direction is `-sign(x - centreX)`. Half-width comes from
a horizontal person-mask scan (24 vertical stations, limited to the midpoint
between the legs so touching thighs are not merged) or from
`fallbackWidthFraction * hipSeparation`. Slimming fades in below the hip and out
above the ankle, and is gated by the person mask.

### Foot / shoe protection

- Lengthening displacement is zero for `y >= anchorAnkle.y`; a lower second
  ankle is also below the anchor, so both feet stay fixed.
- Slimming is exactly zero at and below each leg's own ankle, after a fade over
  `footGuardHeight` above it.
- An ankle within `minimumAnkleMargin` of the bottom or left/right frame edge
  makes the whole pass a safe no-op (`.feetOutsideFrame`), because a cropped
  foot cannot be guaranteed complete.
- A colour/pixel test renders a synthetic shoe block and checks that the red
  foot pixels survive the warp and the frame has no black/transparent border.

### Edge extension / mirroring

- Every contribution is multiplied by `smoothstep(min(x, 1-x) / edgeMargin)`,
  so the left and right frame columns stay pinned and no out-of-frame content is
  requested near a border.
- Leg half-width is additionally clamped to the visible room between the
  centreline and the frame edge (lateral edge extension), so a leg cut by the
  frame is slimmed within the visible part rather than pulling clamp-to-edge
  pixels inward.
- If a person-mask scan is cut by the left/right frame on one side, the visible
  run is mirrored to estimate the missing half-width instead of averaging a
  truncated run with a full one (mask-level mirror extension).
- Residual sub-pixel sampling at the frame is handled by WP-06's
  `clampToEdge` Metal sampler / `BilinearSampler`; this is the pixel-level edge
  fill. The leg pass must not and does not implement image resampling itself.
- The left/right leg profiles are generated independently with mirrored
  directions; synthetic tests assert mirrored offsets.

## Limits

All limits are in `LegsWarpConfiguration` and immutable after creation:

| Limit | Default |
|---|---|
| effective leg length | `1.00...1.15` |
| lateral displacement per leg | `0.030` (normalized x) |
| hip shift / vertical displacement | `0.080` (normalized y) |
| per-vertex contribution | `0.100` (normalized units) |
| minimum body confidence | `0.30` |
| minimum leg length | `0.15` |
| minimum bottom margin | `0.01` |
| face clearance | `0.015` |

The engine's `GeometryBoundaryPolicy` applies a second clamp (`0.25` by default)
and pins/feathers the frame after every pass.

## Safe skips and warnings

`GeometryPass` has no warning channel, so `makePlan(...)` exposes the plan:

```swift
let plan = try LegsWarpContributor().makePlan(
    analysis: analysis,
    parameters: parameters,
    gridWidth: 32,
    gridHeight: 32
)
plan.skipReason        // nil when displacement was produced
plan.warnings          // .noBody, .incompletePose, .feetOutsideFrame, ...
plan.effectiveLegLength
plan.peakDisplacement
plan.didClampToLimit
```

Skips never throw: `.noBody`, `.lowConfidence`, `.incompletePose`,
`.degeneratePose`, `.feetOutsideFrame`, `.neutralParameters`,
`.noUsableRegion`. Occlusion reduces both strengths by `occlusionScale` (0.5)
and reports `.occlusionReduced`.

## Tests

```bash
swift test --filter LegsWarpContributorTests
```

The suite covers: no-body/low-confidence/neutral/incomplete/cropped/crossed
safe skips; mirrored inward contour motion; hip/knee/ankle anchor behaviour;
monotonic bounded lengthening; maximum-length and per-vertex clamps; face
protection; occlusion scaling; frame-edge pinning; person-mask gating;
`plan.applying` compatibility; a synthetic pixel test for black borders and
intact shoes; and a 64×64 1080p planning performance probe
(`ST_LEGS_PERF_STRICT=1` enables the 0.5 s threshold).

### Measured CI baseline

macOS 15 CI, run
[`40114221111`](https://github.com/JHub-Wei/StyleTone/actions/runs/40114221111),
commit `e1d3ab7`, debug build:

- `LegsWarpContributorTests`: **24 tests, 0 failures**.
- `legs.plan.1080p backend=legs.cpu grid=64x64 size=1080x1440 n=8`:
  mean 4.2 ms, p50 4.0 ms, **p95 4.4 ms** (227 fps planning throughput).
- Full `swift test` and the iOS Simulator app test pass on the same run.
- This measures plan construction only; the WP-06 Metal render is the frame
  budget owner. The result still shows the pass is far below its 33.3 ms share.

## Known limitations / risks

- Lengthening is anchored at the ankle, so the hip/crotch line moves up and the
  waist band is compressed. The blend and face guard keep it smooth, but very
  high `legLength` values on tight clothing can still be visible. The learned
  default cap is 1.08, below the manual 1.15 maximum.
- The field has no canvas/crop extension. The pass deliberately never relies on
  generating pixels outside the source image; WP-06 clamp-to-edge is the fill.
- Background straight-line protection is WP-15's job. This pass only restricts
  itself to the person mask/leg spans; it does not detect doors, tiles or
  horizons.
- The pose model is a single `BodyObservation`. Multiple people, crossed legs,
  sitting poses and missing ankles are skipped rather than guessed. No identity
  recognition or body measurement is performed.
