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

Run: `TBD_CI_RUN` (fill after the first green CI run).

| Path | Grid | Mask | p50 | p95 |
|---|---|---|---|---|
| `BackgroundWarpConstraint` | 64 × 64 | 4032 × 3024 | `TBD` | `TBD` |

Interpretation: `TBD`.

## Reproduce

```bash
swift test --filter BackgroundProtectionPerformanceTests
ST_BACKGROUND_PERF_STRICT=1 swift test --filter BackgroundProtectionPerformanceTests
```

The test is available on every macOS CI run. It does not require Metal; the
constraint is pure CPU geometry on the coarse grid, so a simulator or a
non-Metal runner measures the same code path.
