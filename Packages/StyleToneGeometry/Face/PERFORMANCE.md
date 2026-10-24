# Face pass performance (WP-12)

Status: **measured on macOS CI** (macOS 15 arm64 runner, debug `swift test`).
The 32×32 face contribution uses about 3 % of the 30 fps frame budget. The
measurement covers planning only, not the mesh upload or fragment sampling that
WP-06 already benchmarks separately.

## Method

- Tests: `FaceWarpPerformanceTests.testPreviewContributionFitsThirtyFPSBudget`
  and `testExportDensityContributionMeasurement`.
- Inputs: synthetic `PortraitAnalysis` with 1 or 3 faces (no image decode), the
  same landmarks used by the unit tests.
- Parameters: `slim = 0.8`, `jaw = 0.7`.
- Path: `FaceWarpContributor.plan(...)` — face filtering, guard construction and
  the full 32×32 / 64×64 vertex loop. No `WarpField` application, no renderer.
- Timer: `GeometryPerformanceProbe.measure` (`ContinuousClock`), 3 warm-up + 20
  measured iterations for preview and 2 + 10 for export; p95 is reported.
- Budget: 33.3 ms p95 (one 30 fps frame, contracts §5.6).
- Print prefix: `FACE_GEOMETRY_PERF`.

## Baseline

Run: [macOS CI 40112796982](https://github.com/JHub-Wei/StyleTone/actions/runs/40112796982),
2026-10-24, commit `1258114`, macOS 15 arm64, debug build.

| Path | Grid | Faces | p50 | p95 | p95 fps |
|---|---|---|---|---|---|
| contribution | 32×32 | 1 | 0.5 ms | **0.5 ms** | **1851.7** |
| contribution | 32×32 | 3 | 1.0 ms | **1.0 ms** | **1024.4** |
| contribution | 64×64 | 3 | 3.3 ms | **3.4 ms** | **295.0** |

At preview density the 3-face contribution uses about 3 % of the 33.3 ms frame
budget (≈33× headroom). At export density it is a one-shot cost, still around
1/10 of a preview frame.

## Interpretation and caveats

- This is the WP-12 contribution only. WP-06's mesh build/render dominates the
  interactive frame; see `Packages/StyleToneGeometry/Core/PERFORMANCE.md`.
- Debug builds are slower than release; device release performance should be at
  least as good. Re-run on an iPhone 13 reference device before release if the
  contribution changes materially.
- The test asserts the 33.3 ms budget unconditionally (the pass must not consume
  a frame). For a stricter watermark on a reference device, compare the printed
  `FACE_GEOMETRY_PERF` line against the baseline above.
- The full CI job ran 579 tests (4 skipped) with 0 failures; WP-12 adds 16
  behaviour tests and 2 performance tests.

## Reproduce

```bash
swift test --filter FaceWarpPerformanceTests
# or the whole geometry suite
swift test --filter StyleToneGeometryTests
```
