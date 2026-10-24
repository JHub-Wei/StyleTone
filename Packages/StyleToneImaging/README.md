# StyleToneImaging (WP-02)

Decode, orient, color-convert and encode images. This package owns every
pixel-format and color-space decision below the rendering algorithms.

## Public surface

| Type | Purpose |
|---|---|
| `ImageLoader` | HEIC/JPEG/PNG decode, EXIF orientation, downsampling, error classification |
| `ImageLoadOptions` | `.fullResolution`, `.preview` (2048 px), minimum long edge, target color space |
| `ColorPipeline` | sRGB ↔ extended linear sRGB, Display P3 input, gamut mapping, tile access |
| `LinearImage` | Straight-alpha, extended linear sRGB `Float32` RGBA buffer |
| `ImageWriter` | HEIC/JPEG encoding with quality and an explicit output color space |
| `ImageWriteOptions` | Format, quality, color space |
| `FileImageExporter` | `ImageExporting` implementation writing to `<tmp>/StyleToneExports` |

## Color policy

- Exchange pixels are 8-bit per channel with premultiplied alpha; orientation
  is already applied.
- **Import** preserves Display P3 when the source carries a P3 profile, because
  converting to sRGB at import would clip wide-gamut data before rendering.
  `ImageAsset.colorSpace` records the actual space. Pass
  `ImageLoadOptions(targetColorSpace: .sRGB)` for the strict sRGB baseline.
- **Rendering** always works in extended linear sRGB (`LinearImage`). Display
  P3 values become components below `0` or above `1` instead of being clipped.
- **Export** defaults to sRGB. Values outside the target gamut are mapped by
  holding OKLab lightness and hue and reducing chroma until the color fits, so
  no channel clips abruptly and neutrals are untouched.
- Alpha is straight in `LinearImage` and premultiplied on output; HEIC/JPEG
  exports composite transparent pixels over white.

## Error classification

All loader errors are `StyleToneError` values:

| Situation | Error |
|---|---|
| Empty data, unreadable/missing URL | `.invalidImage` |
| Unknown or truncated image payload | `.imageDecodingFailed` |
| GIF/TIFF or other unsupported format | `.unsupportedFormat` |
| Source long edge below `minimumLongEdge` | `.imageTooSmall(minimumLongEdge:)` |

Writer failures surface as `.exportFailed`; a cancelled `FileImageExporter`
export removes the partial file and throws `CancellationError`.

## Memory and performance

- `ImageLoadOptions.preview` bounds the long edge to 2048 px and never changes
  the aspect ratio.
- `ColorPipeline.forEachTile(in:tileHeight:)` linearizes only one horizontal
  strip at a time; each tile is ~`width × tileHeight × 16` bytes instead of the
  full `width × height × 16` buffer. Use it for 12 MP/48 MP work.
- Decoding runs on a detached task from the async `ImageLoader.load` methods.
- Data access goes through 256-entry decode and 4097-entry encode lookup tables;
  gamut mapping only runs for out-of-gamut pixels.

## Tests

`swift test --filter StyleToneImagingTests` (macOS, since CoreGraphics/ImageIO
are Apple frameworks):

- HEIC/JPEG/PNG decode, Display P3 preservation and forced sRGB
- EXIF orientations 3, 6 and 8 on a block pattern, plus orientation + downsample
- 4:3 preview downsampling
- corrupt, truncated, unsupported and too-small inputs
- sRGB transfer round-trip, known values, gradient round-trip
- P3 → extended linear sRGB, gamut mapping and neutral preservation
- alpha (un)premultiplication and tile/full-image equivalence
- HEIC/JPEG encoding, ICC profile checks via decoded color space, GPS stripping,
  quality-size behavior, alpha flattening and file output
