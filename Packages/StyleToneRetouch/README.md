# StyleToneRetouch (WP-07)

Masked skin smoothing, low-frequency skin evenness and patch-based blemish
repair. The package owns no UI, no undo stack and no image I/O; it consumes
`ImageAsset` + `PortraitAnalysis` and returns a new immutable `ImageAsset`.

## Public surface

| Type | Purpose |
|---|---|
| `SkinRetoucher` | Stateless engine; conforms to `RetouchRendering` and `BlemishRemoving` |
| `SkinRetouchConfiguration` | Tunable radii/strengths; `.standard` is the production default |

```swift
let engine = SkinRetoucher()
let smoothed = try await engine.retouch(
    image,
    analysis: analysis,                 // needs a same-size skinMask
    parameters: SkinParameters(smoothing: 0.7, evenness: 0.4)
)
let repaired = try await engine.removeBlemishes(
    smoothed,
    at: points,                         // [BlemishPoint], empty = no-op
    analysis: analysis
)
```

`RetouchRendering` only uses `smoothing` and `evenness`. The frozen protocol has
no blemish-point argument; `SkinParameters.blemish` is the UI slider that decides
whether the UI collects points, while the actual repair goes through
`BlemishRemoving`. `RenderRequest.blemishPoints` is the integration point in
WP-17. Undo belongs to the editor: the engine returns a new asset and keeps no
state.

Every call runs on a detached user-initiated task. Cancellation propagates as
`CancellationError`; no partial image is returned.

## Algorithm

### Frequency bands

Skin is converted to extended linear sRGB by `ColorPipeline` (never sRGB math in
the module). For luma `Y`, two scales are used:

- `G1`: self-guided filter, radius `0.0045 × shortEdge`, epsilon `0.0004`.
- `G2`: regional low-pass, radius `0.04 × shortEdge`, built from a downscaled
  copy (at most 8×) and bilinearly upsampled.

Bands: `fine = Y − G1`, `mid = G1 − G2`, `low = G2`. This is classic
high-frequency separation with a guided filter instead of a Gaussian.

```
Y' = G2 + (G1 − G2) × (1 − 0.55·evenness)
        + (Y − G1) × (1 − 0.58·smoothing)
```

- At `smoothing = 1`, 42 % of the pore band is retained, so edges and texture
  survive; the guided filter itself follows strong edges and leaves them intact.
- At `evenness = 1`, 45 % of the regional band is retained. The change per pixel
  is hard-clamped to `±0.035` linear luma, so evenness can only redistribute
  local energy, never add a brightening offset.
- An edge weight `1 / (1 + (|fine| / 0.035)²)` fades evenness out on strong
  structures (eyes, lips, hair, backdrop lines).
- Chroma is treated separately: Cb/Cr are low-passed at the G2 scale and blended
  at most 40 % at `evenness = 1`. Luma is reconstructed with the inverse Rec.709
  YCbCr transform, so hue and saturation stay stable and there is no whitening.
- The mask alpha is applied after the frequency math, so the background and
  partly masked edges keep their original pixels.

### Facial-feature guard

When landmarks exist, eyes, eyebrows, pupils and outer lips are rasterised into
a feathered guard and multiplied into the skin mask. This protects coarse
masks (the WP-04 ellipse mock is one) without needing a production-quality
Vision mask. No skin-tone classification or identity data is used.

### Blemish repair

`BlemishRemoving` works in linear light on a disk of
`radius × shortEdge` (`0.005...0.08` per the core contract):

1. Fit a plane `c + gx·u + gy·v` to an annulus at `1.02...1.50 r`; the plane
   carries local shading into the fill.
2. Search 16 angles × 3 distances (`1.6 r`, `2.2 r`, `2.9 r`) for the source
   patch whose shifted annulus best matches the target annulus. Source skin
   coverage and source-centre colour are penalties, not hard filters, so small
   objects on clothing still work when no mask is present.
3. Transfer only source high-frequency detail (`source − boxBlur(source, 0.25 r)`),
   clamped to `3 × ring texture σ` (0.012...0.06). This keeps pores and stops a
   second blemish in the source patch from being copied.
4. Composite with a smooth ramp from `0.72 r` to `r`. No pixel outside the disk
   is written. If no source patch fits (image border), the plane fill is used
   instead of failing.

The plane fit, source search and detail clamp are all local: the cost and the
changed region scale with the requested radius, not with the image area. A
batch API linearises/encodes once for all points.

## Safe degradation

| Situation | Result |
|---|---|
| `smoothing == 0 && evenness == 0` | Original `ImageAsset` (bit-identical, same `CGImage`) |
| `skinMask == nil` | Original |
| Mask size ≠ image size | Original |
| Empty / near-empty mask, or mask fully guarded | Original |
| Regional field cannot be built | Smoothing only; evenness disabled |
| Blemish point outside `0...1`, NaN, empty point list | Original |
| No source patch fits (border / tiny image) | Local plane fill, or original if no ring |
| 1×1 image, huge radius | No crash; original or tiny local fill |

## Performance

- Horizontal bands of 384 rows (configurable) with a `2r+1` halo; only one
  linear band is alive at a time. Output is one full RGBA float buffer, then one
  8-bit encode buffer.
- Guided filter and box blur are O(pixels) separable sliding-window passes.
- Evenness builds a ≤1/8-scale luma/chroma field; the 12 MP field is roughly
  0.5 MP per plane.
- 12 MP retouch is the acceptance budget (`≤2 s`, target device). It is opt-in
  in XCTest because debug builds are not a valid measurement:

```bash
# macOS Release/device run
ST_RUN_RETOUCH_12MP_PERF=1 swift test --filter RetouchPerformanceTests
```

The always-on 512×512 test is a regression guard only. Worst-case peak memory
for 12 MP retouch is roughly 400 MB (output float buffer dominates); blemish
removal on 12 MP is roughly 480 MB because the full linear input is mutable.

## Tests

```bash
swift test --filter StyleToneRetouchTests
```

- strength 0 returns the same `CGImage`; missing/empty/wrong-size masks no-op;
  NaN parameters no-op
- synthetic texture: max smoothing keeps >20 % high-frequency energy and shifts
  mean luma by <1.5/255
- six Fitzpatrick I–VI synthetic tones: brightness, saturation and hue stay
  within 1/255, 1.5 % and 1.5°; texture is retained
- evenness lowers 8×8 regional variation by >8 % without removing fine texture
- a hard step edge keeps >85 % contrast at maximum smoothing + evenness
- landmark guard leaves eye pixels bit-identical
- blemish: dark spot moves to the ring mean, outside the disk changes by ≤1
  level after encode, batch repair and no-mask repair work
- invalid/NaN/out-of-bounds points, 1×1 image and border points are safe
- 512×512 performance guard and opt-in 12 MP envelope

## Risks / open items

- `≤2 s` for 12 MP is a release/device target. The implementation is scalar
  Swift; if the first device measurement misses the budget, the next step is
  Accelerate/vDSP vectorisation of the box-filter rows, not a quality reduction.
- The low-frequency chroma field is intentionally subtle. Stronger evenness
  would need a perceptual (OKLab) target and a wider blind-test set; the current
  cap is what keeps dark tones from going grey.
- Blemish repair assumes the selected disk is mostly skin. It is local and
  leaves structure outside the disk, but a very large radius over an eye will
  replace that area; WP-16 should keep the default radius small.
- WP-05 masks are trusted for size and coverage. A stale mask (different photo)
  is rejected by size only; the feature guard is the second line of defence.
- No Metal path yet; WP-24 owns GPU/render optimisation.
