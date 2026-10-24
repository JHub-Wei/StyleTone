# StyleToneLearning (WP-11)

Local style learning for `StyleProfile` schema 3. The module turns 3–8
original/edited pairs plus 6–8 AB choices into a conservative personal profile:
tone, white balance, saturation, retouch strength, geometry defaults, finish and
confidence. It does no face/body detection, no networking and no persistence.

## Public surface

| Type | Purpose |
|---|---|
| `StyleLearningEngine` | `StyleLearning` implementation; stateless `Sendable` struct |
| `StyleLearningRequest` | Pairs + answers + optional per-pair strength signals |
| `StyleLearningResult` | Profile plus non-persisted diagnostics |
| `PairStrengthSignals` | Optional landmark/contour strengths from integration |
| `StyleSafetyRanges` | Enforced output envelope (see below) |
| `SkinProtectionConfiguration` | Chroma/hue guard limits |
| `StyleLearningConfiguration` | Proxy edge, thresholds, confidence counts |
| `StyleLearningIssue` | Explainability codes (outliers, skipped pairs, clamping) |

The frozen `StyleLearning.learn(samples:answers:)` entry point returns just the
profile. Use `learn(_ request:)` when you can supply strength signals or want
diagnostics.

```swift
let engine = StyleLearningEngine()
let result = try await engine.learn(
    StyleLearningRequest(samples: pairs, answers: abAnswers)
)
// result.profile: StyleProfile (schemaVersion 3, algorithmVersion st-3.0.0)
// result.diagnostics: why the confidence is what it is
```

## Algorithm

### 1. Pair filtering and sampling

- `rejected` pairs are excluded; `warning` pairs are kept at 0.55 weight and
  multiplied by `PairQuality.confidence`.
- Each image is drawn into a colour-managed sRGB proxy whose longest edge is
  256 px (configurable). The proxy is private and freed after the call.
- Aspect-ratio mismatch halves the pair weight and raises
  `mismatchedPair`. Unreadable or too-small images are skipped, never fatal.

### 2. Tone, white balance and saturation

Per pair, robust distribution statistics replace pixel alignment:

- Luma quantiles at 2/5/10/25/50/75/90/95/98 % are computed on the proxy.
- Exposure comes from the ratio of linear median luma.
- Contrast comes from the slope of edited-vs-original luma quantiles.
- Highlight/shadow adjustments come from the residual at the top/bottom
  quantile after removing the fitted line.
- White balance is fitted only on near-neutral, non-skin pixels using median
  linear channel logs. Temperature is the red/blue axis, tint the
  green/magenta axis.
- Saturation compares relative chroma (chroma/luma) after normalising edited
  pixels by the fitted white-balance gains, so warmth is not double-counted as
  saturation.
- Skin-like pixels (YCbCr + Lab hue/chroma likelihood, no face detection) are
  excluded from white balance and saturation. After fitting, a skin guard
  measures mean skin chroma and hue. If chroma gain exceeds 1.12 or hue rotates
  more than 6°, the offending temperature/tint/saturation values are scaled
  back. This is the "肤色保护" requirement.

Pair estimates are aggregated by four passes of quality-weighted robust
reweighting: pairs far from the consensus get exponentially smaller weight.
A symmetric 50/50 disagreement stays centred; a single mis-edited export is
pushed toward zero weight.

### 3. Retouch and geometry strengths

- Smoothing, evenness and blemish are estimated from skin-masked high-frequency
  texture loss: mean squared Laplacian, 8×8 regional variation and the 99th
  percentile Laplacian, respectively.
- Face, body and leg strengths are **not** guessed from pixels. They come from
  `PairStrengthSignals` (landmark/contour displacement normalised by the
  integration layer) or from AB preferences. Without evidence they stay at the
  neutral value, which satisfies "不自动应用高强度形变".
- Every value is clamped to `StyleSafetyRanges` before and after aggregation.

### 4. 3/5/8 shrinkage and hold-out validation

Leave-one-out validation re-aggregates the other pairs and measures the
normalised parameter distance to the held-out pair. The result is a weighted
RMS of the five largest component differences, `0...1`. An unavailable hold-out
(fewer than 3 pairs) forces `trial`.

Shrinkage toward the natural default:

| Accepted pairs | Base shrink | Confidence |
|---|---|---|
| 0–2 | 0.15–0.22 | trial |
| 3 | 0.35 | trial |
| 4 | 0.55 | trial |
| 5 | 0.72 | standard |
| 6 | 0.82 | standard |
| 7 | 0.90 | standard |
| 8+ | 1.00 | stable if hold-out ≤ 0.30 |

Quality and hold-out error scale the shrink further down:
`base × (0.65 + 0.35 × meanQuality) × (1 − 0.45 × holdoutError)`.
`stable` additionally requires mean quality ≥ 0.75; `standard` requires ≥ 0.5
and hold-out ≤ 0.50.

### 5. AB preferences

`CalibrationAnswer.strengthDelta` is the signed preference for more (+) or less
(−) strength. `choseA` is retained by the UI/analytics but **not** used for
direction, because the UI may place either candidate on side A.

Each dimension maps to a small bounded nudge; six answers reach full influence,
fewer are scaled down:

| Dimension | Parameters |
|---|---|
| `tone` | exposure, contrast, saturation |
| `skinTone` | temperature, tint, evenness |
| `smoothing` | smoothing, evenness, blemish |
| `faceSlim` | slim, jaw |
| `bodySlim` | arm, waist, leg |
| `legLength` | leg length |
| `naturalness` | global strength scale, slight contrast/saturation |

A single dimension with six unanimous answers changes a strength by at most
0.06 before safety clamping. AB is applied after shrinkage, so 3-pair profiles
remain conservative.

### 6. Tags and metadata

`algorithmVersion` is `st-3.0.0`; `schemaVersion` is 3. Tags are localization
keys using the WP-10 vocabulary: `style.tag.natural`, `style.tag.warm`,
`style.tag.soft`, `style.tag.defined`, `style.tag.editorial`.
`updatedAt` comes from the injected `DateProviding`, which makes tests
deterministic.

## Parameter ranges

`StyleSafetyRanges.standard` (all signed values are ±):

| Parameter | Range |
|---|---|
| exposure | ±0.35 |
| contrast | ±0.45 |
| highlights / shadows | ±0.50 |
| temperature | ±0.40 |
| tint | ±0.35 |
| saturation | ±0.45 |
| smoothing | 0…0.55 |
| evenness | 0…0.50 |
| blemish | 0…0.45 |
| face slim | 0…0.35 |
| jaw | 0…0.30 |
| arm / waist / leg | 0…0.30 |
| leg length | 1.00…1.08 |
| grain | 0…0.15 |
| vignette | −0.18…0 |

Core parameter initialisers clamp to the wider contract ranges; this module
clamps to the narrower envelope above on every output path, including AB-only
profiles.

## Safe degradation

| Situation | Result |
|---|---|
| No samples, no answers | Natural trial profile, `pairCount = 0` |
| All pairs rejected | Natural trial profile; `rejectedPair`, `noValidPairs` |
| Unreadable/too-small pair | Skipped; remaining pairs still learned |
| Only AB answers | Trial profile from neutral base; `abOnly` |
| Fewer than 3 pairs | `trial`, heavy shrink, `holdoutUnavailable` |
| High disagreement | Hold-out error raises; `stable` withheld |
| Single outlier | Down-weighted; `outlierPair` diagnostic |
| NaN answer delta | Ignored; `answeredCount` excludes it |
| 16×16 or mismatched aspect | Learned/neutral safely; warning diagnostics |
| Cancellation | Throws `CancellationError`; no partial profile |

## Performance

The proxy caps work at 256 px per image. Five synthetic 160×160 pairs complete
in well under a second on the macOS CI runner; the acceptance budget is 90 s for
five pairs and 150 s for eight. The test suite records both durations as
attachments and asserts the budget.

## Tests

```bash
swift test --filter StyleToneLearningTests
```

Coverage:

- warm/cool exposure, contrast, saturation, neutral pairs
- skin-chroma guard reduces an over-saturated skin edit
- extreme edits clamped to the safety envelope
- texture-loss smoothing estimate, signal clamping, no automatic geometry
- AB direction, negative naturalness, AB-only, bounded influence, determinism
- 3-pair strong shrink vs 8-pair stable, 5-pair standard + time budget
- disagreement raises hold-out error; single outlier does not drag the profile
- empty/rejected/tiny/mismatched/NaN inputs, cancellation
- protocol vs detailed entry point, deterministic date
- schema-3 JSON round-trip and algorithm version
- 5-pair/8-pair performance budgets

## Risks / open items

- Skin likelihood is colour-only. A strongly skin-coloured background or
  clothing can be counted as skin; the guard then becomes slightly more
  conservative, never more aggressive. Production face/skin masks are owned by
  WP-05 and could be passed as signals later.
- Geometry strengths depend on integration supplying `PairStrengthSignals`.
  The protocol path intentionally leaves them neutral rather than guessing body
  shape.
- Hold-out validation is parameter-space consistency, not a rendered-image
  metric. A future WP-25 golden set can replace it with perceptual error.
- Confidence thresholds (0.30 / 0.50) are calibrated on synthetic pairs and
  need validation with authorised real pairs before Phase B.
- `StyleProfile` has no field for recommended global strength or max strength;
  the editor's natural default (70 %) remains WP-17's responsibility.
- No network, no identity recognition, no persisted diagnostics by design.
