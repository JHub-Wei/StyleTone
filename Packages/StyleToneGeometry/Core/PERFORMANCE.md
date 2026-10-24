# Geometry performance baseline (WP-06)

Status: **measurement pending** — filled from the macOS CI `swift test` log.
The harness is part of `StyleToneGeometryTests` and runs 1920×1080 frames with a
synthetic displacement field.

## Method

- Test: `MetalGeometryWarpTests.test1080pPreviewAndExportPerformance`.
- Image: 1920×1080 opaque sRGB gradient, created once per test.
- Preview path: `MetalGeometryWarp.renderTexture` (compute mesh build + render
  pass into an offscreen texture, no CPU readback), 3 warm-up + 8 measured
  frames.
- Export path: `MetalGeometryWarp.warp` (same plus texture readback and
  `CGImage` creation), 1 warm-up + 4 measured frames.
- Timer: `ContinuousClock` via `GeometryPerformanceProbe`; report uses p95.
- Budget: 33.3 ms p95 for the preview path (30 fps, contracts §5.6).
- CI asserts the budget only when `ST_GEOMETRY_PERF_STRICT=1`; runners are not
  reference devices. The printed `GEOMETRY_PERF` line is the recorded baseline.

## Baseline

| Date | Runner | Device | Backend | Path | Grid | p50 | p95 | p95 fps |
|---|---|---|---|---|---|---|---|---|
| _pending_ | macos-15 | _pending_ | geometry.metal | preview (no readback) | 32×32 | _pending_ | _pending_ | _pending_ |
| _pending_ | macos-15 | _pending_ | geometry.metal | export (+ readback) | 64×64 | _pending_ | _pending_ | _pending_ |

CPU backend numbers are intentionally not a target: `CPUGeometryWarp` is the
reference/fallback path and is expected to be well below 30 fps at 1080p.

## Reproduce

```bash
swift test --filter MetalGeometryWarpTests/test1080pPreviewAndExportPerformance
# Optional, on a reference iPhone:
ST_GEOMETRY_PERF_STRICT=1 swift test --filter MetalGeometryWarpTests
```

On a runner without a Metal device the test is skipped with
`XCTSkip("Metal device unavailable on this runner")`.
