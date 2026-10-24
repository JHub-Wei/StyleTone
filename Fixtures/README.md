# Fixtures

Deterministic, synthetic test assets for StyleTone. **No real user photos are
committed here** and nothing in this directory is downloaded at build or test
time.

## Layout

```text
Fixtures/
├── manifest.json          # catalog of the 10 synthetic fixtures (checked in)
├── reference/             # 8-bit sRGB RGBA PNGs generated from the catalog
│   ├── solid-cream.png
│   └── …                  # exactly the files named by manifest.json
└── samples/               # authorized real-photo slot (photos git-ignored)
    ├── .gitignore
    └── manifest.json      # metadata only; starts with zero samples
```

`manifest.json` is the contract:

- `schemaVersion` is `1`.
- `generatorVersion` is the version of the Python generator.
- `fixtures[].referenceSHA256` is the SHA-256 of the PNG bytes, so a swapped or
  recompressed image is detected by the self-check.
- `fixtures[].referenceFile` is relative to `reference/`.
- Colours are uppercase `#RRGGBB`.

## The ten fixtures

| id | kind | size | purpose |
|---|---|---|---|
| `solid.cream` | solid colour | 64×64 | alpha/colour/ICC round-trip |
| `gradient.gray-horizontal` | linear gradient | 256×64 | monotonic luma ramp |
| `gradient.warm-vertical` | linear gradient | 192×128 | warm vertical ramp |
| `checkerboard.8px` | checkerboard | 128×96 | alignment/sampling |
| `colorchart.macbeth24` | colour chart | 240×160 | colour pipeline, ΔE00 |
| `colorchart.skintones` | colour chart | 180×120 | skin tone I–VI safety |
| `noise.midgray` | noise | 128×128 | deterministic grain/denoise |
| `edge.vertical` | vertical edge | 160×120 | geometry boundaries |
| `grid.tiles` | grid | 192×144 | straight lines/background protection |
| `face.silhouette` | face outline | 192×256 | landmarks/UI placeholder (cartoon, not a person) |

These cover the seven requested pattern families: solid, gradient,
checkerboard, colour chart, noise, straight lines/edges and a simple face
outline. The face fixture is deliberately a symmetric cartoon; it is not a
rendering or composite of any real person.

### Colour order by kind

| kind | `colors` |
|---|---|
| `solidColor` | `[fill]` |
| `linearGradient` | `[from, to]` (+ `axis`) |
| `checkerboard` | `[light, dark]` (+ `cellSize`) |
| `colorChart` | `[patch0 …]` (+ `columns`) |
| `noise` | `[base]` (+ `amplitude`, `seed`) |
| `verticalEdge` | `[left, right]` (+ `edgeX`) |
| `grid` | `[background, line]` (+ `spacing`, `lineWidth`) |
| `faceSilhouette` | `[skin, hair, background, eye, lips, shirt]` |

## Consuming fixtures from Swift

`GoldenSupport` embeds the same catalog, so tests do not need file I/O:

```swift
import GoldenSupport

let image = try FixtureCatalog.fixture(id: "colorchart.macbeth24").imageAsset()
let pixels = try FixtureCatalog.fixture(id: "face.silhouette").render()
```

The committed PNGs are available to decode/orientation tests through
`TestShared.TestEnvironment`:

```swift
let environment = TestEnvironment()
let url = environment.referenceDirectory!.appendingPathComponent("edge-vertical.png")
```

`FixtureColorProbe`s describe a handful of pixels that both the Swift renderer
and the reference PNG must satisfy. Use them for cheap structural checks.

## Regenerating

The generator is a developer tool (Pillow required; CI never runs it):

```bash
python Tests/GoldenSupport/Tools/generate_fixtures.py
# copy the staged Swift catalog from Fixtures/.build/ into
# Tests/GoldenSupport/Sources/GoldenSupport/FixtureCatalogData.swift
python Tests/GoldenSupport/Tools/generate_fixtures.py --verify
```

`--verify` checks the manifest, the Swift catalog and every reference PNG hash
and probe. The same invariants are asserted by `FixtureSelfCheckTests` on
macOS CI.

## Authorized real-photo samples

Real photos are added later by the project owner, **outside version control**:

1. Put the files in `Fixtures/samples/` (already git-ignored: only
   `.gitignore` and `manifest.json` are tracked).
2. Add a metadata entry to `Fixtures/samples/manifest.json`; never add an
   absolute path or a path containing `..`.
3. Keep the consent/license reference in `license` and the authorizing person
   in `authorizedBy`.

Schema (`AuthorizedSample` in `GoldenSupport`):

```json
{
  "schemaVersion": 1,
  "description": "Authorized real-photo samples are never committed.",
  "samples": [
    {
      "id": "sample-001",
      "fileName": "portrait-001.jpg",
      "category": "portrait",
      "skinTone": 4,
      "bodyType": "standard",
      "license": "written-consent-2026-01",
      "authorizedBy": "project-owner",
      "addedAt": "2026-01-01T00:00:00Z",
      "notes": "studio, window light"
    }
  ]
}
```

`category` is one of `portrait`, `pair-original`, `pair-edited`, `background`.
`skinTone` is `1...6` (Fitzpatrick I–VI). Tests assert that the manifest is
valid **and** that no image file is committed under `Fixtures/samples/`.

## Rules

- No network access, ever.
- No real user photos, no faces derived from photos.
- No EXIF/location data: assets are generated, not captured.
- Reference PNGs are 8-bit sRGB, premultiplied-alpha-compatible and opaque.
- Fixture generation is deterministic: same generator version + Pillow version
  produces byte-identical PNGs.
