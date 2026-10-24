# Geometry performance baseline (WP-06)

Status: **measured on CI** (macOS 15, Apple Paravirtual GPU). The 1080p preview
budget of 30 fps is met; an iPhone 13 reference run is still recommended before
release.

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
- CI asserts the budget only when `ST_GEOMETRY_PERF_STRICT=1`; the recorded
  line is the baseline.

## Baseline

Run: [macOS CI 40100281123](https://github.com/JHub-Wei/StyleTone/actions/runs/40100281123),
2026-10-24, commit `c670a48`, device `Apple Paravirtual device`, debug build
(`swift test`).

| Path | Backend | Grid | p50 | p95 | p95 fps |
|---|---|---|---|---|---|
| preview, no readback | `geometry.metal` | 32×32 | 21.5 ms | **25.3 ms** | **39.6** |
| export, texture readback + CGImage | `geometry.metal` | 64×64 | 38.0 ms | 38.4 ms | 26.0 |
| 1080p CPU fallback (reference only) | `geometry.cpu` | 32×32 | 4.356 s | 4.356 s | 0.2 |

Interpretation:

- The preview path meets the 1080p 30 fps target on the CI paravirtual GPU with
  headroom (39.6 fps p95). The measured path includes per-frame source texture
  upload and allocation, so a real preview that keeps the source texture and
  draws to a `CAMetalLayer` should be faster.
- Export includes an 8.3 MB GPU→CPU readback and `CGImage` creation; it is a
  one-shot operation, not an interactive budget. 64×64 export at 26 fps still
  bounds a 12 MP export well within the 6 s export budget once tiled.
- The CPU backend is a correctness/reference fallback, not a preview path. It is
  intentionally not optimized to 30 fps.
- Memory for the Metal preview path is the source texture (8.3 MB), render
  target (8.3 MB) and small mesh/offset buffers, far below the 300 MB preview
  budget.

## Reproduce

```bash
swift test --filter MetalGeometryWarpTests/test1080pPreviewAndExportPerformance
# Optional, on a reference iPhone:
ST_GEOMETRY_PERF_STRICT=1 swift test --filter MetalGeometryWarpTests
```

On a runner without a Metal device the test is skipped with
`XCTSkip("Metal device unavailable on this runner")`. `MetalShaderCompilationTests`
still compiles the embedded MSL with `xcrun metal` on every macOS CI run.
