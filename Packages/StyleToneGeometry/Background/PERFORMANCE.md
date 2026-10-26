# Background protection performance (WP-15)

Status: **measured on CI** (macOS 15 runner, debug build). The strict budget is
opt-in via `ST_BACKGROUND_PERF_STRICT=1`, matching WP-06.

## Method

- Test: `BackgroundProtectionPerformanceTests/testConstraintWith12MegapixelEdgeMask`.
- Input mask: synthetic `4032 × 3024` (12.2 MP) edge mask with five vertical and
  four horizontal lines, 6 px wide. The mask is built once; it is not decoded
  from an image.
- Warp field: `64 × 64` vertices, 2 % sine wave. One warm-up run, six measured
  runs of `BackgroundWarpConstraint.constrain` (mask sampling + detection +
  protection + metrics). The field copy per run is outside the timing loop's
  intent but included; it is a 4096-entry array.
- Timer: `ContinuousClock`; p50 and p95 printed as
  `BACKGROUND_CONSTRAINT_PERF`.
- Budget: no frozen frame budget for the constraint. The acceptance target is
  "not a visible preview regression": the strict debug budget is 400 ms p95 for
  the 12 MP mask, which corresponds to a few milliseconds in a release build on
  a phone. The non-strict run only guards against hangs (2 s).

## Why a 12 MP mask

WP-05 builds the structure mask at proxy resolution but resamples it to the
input's pixel size, so the constraint can receive a 12 MP mask. The sampler
reads at most `maximumMaskSamples` (default 1.5 M) bytes and uses a stride of 4
at 12 MP; the WP-05 mask is dilated/blurred, so a 4 px stride cannot miss a
line. Smaller masks (≤ 2 MP) are read every pixel for exact test geometry.

## Baseline

Run: [40162439838](https://github.com/JHub-Wei/StyleTone/actions/runs/40162439838),
2026-10-25, commit `bf51ab2`, macOS 15 arm64 runner, debug build (4 measured
runs, 1 warm-up).

| Path | Grid | Mask | p50 | p95 |
|---|---|---|---|---|
| `BackgroundWarpConstraint` | 64 × 64 | 4032 × 3024 | **91.76 ms** | **92.56 ms** |

Interpretation:

- The CI number is a **debug** build. The hot loop is simple scalar mask
  sampling; release builds typically remove most of the debug overhead, so the
  expected on-device cost is in the single-digit-to-low-tens-of-milliseconds
  range. A release-mode measurement on a reference iPhone is still recommended
  (WP-24) before locking the preview budget.
- The 12 MP mask is the worst case. The preview warp uses a 32 × 32 grid, but
  the cost is dominated by mask sampling rather than the per-vertex loops, so
  preview and export are expected to be close. The analysis can be reused across
  frames; the constraint itself caches nothing.
- The 2 s hang guard is far above the measured value. The strict 400 ms debug
  budget passes with ~4× headroom (`p95 = 92.56 ms`).

Possible optimization if a device measurement shows a problem: raise
`maskSamplingStride` from 4 to 8 (halves mask reads; the WP-05 mask is ≥ 20 px
wide at 12 MP, so detection remains safe) or cache the sampled structure grid
for an unchanged analysis.

## Reproduce

```bash
swift test --filter BackgroundProtectionPerformanceTests
ST_BACKGROUND_PERF_STRICT=1 swift test --filter BackgroundProtectionPerformanceTests
```

The test is available on every macOS CI run. It does not require Metal; the
constraint is pure CPU geometry on the coarse grid, so a simulator or a
non-Metal runner measures the same code path.
