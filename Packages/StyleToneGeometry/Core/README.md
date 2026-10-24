# StyleToneGeometry Core (WP-06)

Reusable mesh-warp engine for the geometry stage. It contains **no face, body
or leg shape logic**; those live in `Sources/StyleToneGeometry/{Face,Body,Legs}`
and contribute through the frozen protocols in `contracts.md` §4.1.

## Pipeline

```
GeometryParameters + PortraitAnalysis
        │
        ├─ GeometryPass (.face)   [WP-12]
        ├─ GeometryPass (.body)   [WP-13]
        ├─ GeometryPass (.legs)   [WP-14]
        ├─ GeometryConstraint(s)  (registration order)
        ├─ GeometryConstraint background (only if backgroundProtection) [WP-15]
        ├─ boundary pinning + smoothstep feather + magnitude clamp
        ▼
   WarpField (32×32 preview / 64×64 export)
        │
        ├─ MetalGeometryWarp  (compute mesh build + render mesh)
        └─ CPUGeometryWarp    (reference/fallback)
        ▼
   ImageAsset (same size and colour space)
```

`GeometryRenderingEngine` is an actor implementing `StyleToneCore.GeometryRendering`.
`GeometryPipeline` is the synchronous, testable heart of the engine.

## Field semantics

`WarpField` is a regular grid, row-major, `width * height` entries, with vertex
`(0,0)` at normalized `(0,0)` (top-left). An offset is the **content
displacement** at that vertex: positive `x` moves content right, positive `y`
moves it down. The mesh therefore keeps its vertices fixed in output space and
uses `uv = gridPosition - offset` as the texture coordinate. This is an inverse
map expressed as a forward displacement, which has three useful properties:

1. the mesh always covers the frame (no holes/black gaps);
2. boundary vertices can be pinned to zero displacement;
3. the mapping is single-valued, so CPU and GPU sampling can agree exactly.

`GeometryBoundaryPolicy` (default: 1 pinned ring, 4 feather cells, max offset
0.25) is applied after all contributions. The Metal sampler is additionally
`clampToEdge`, so a malicious/large offset cannot expose uninitialised texels.

## Integrating a pass (WP-12/13/14)

```swift
public struct FaceWarpPass: GeometryPass {
    public let identifier = "face.slim"
    public func contribute(
        to field: inout WarpField,
        analysis: PortraitAnalysis,
        parameters: GeometryParameters
    ) throws {
        // Read analysis.faces and parameters.face, add displacements with
        // field.addOffset(_:x:y:). Do not resize the field.
    }
}

let engine = GeometryRenderingEngine(
    passes: [GeometryPassEntry(phase: .face, pass: FaceWarpPass())],
    backgroundConstraint: BackgroundWarpConstraint(),
    configuration: .preview
)
```

Constraints only receive `analysis` by contract; the background constraint is
separately registered and toggled by `backgroundProtection`.

## Backends

- `MetalGeometryWarp` — one command buffer per frame: a compute kernel expands
  the field into vertices, a render pass draws the indexed mesh into an
  `rgba8Unorm_srgb` target, then the texture is read back (or kept for preview).
- `CPUGeometryWarp` — converts through `ColorPipeline` to linear sRGB, applies
  the same triangle interpolation and bilinear clamp-to-edge sampling, then
  encodes back. Used by tests and as a fallback; not the 30 fps path.

Identity shortcut: when the final field is zero and
`allowsIdentityShortcut` is true, the engine returns the exact input
`ImageAsset` without a colour round trip.

## Tests and performance

```bash
swift test --filter StyleToneGeometryTests
```

The performance test renders 1920×1080 frames, prints a
`GEOMETRY_PERF` line and only asserts the 33.3 ms preview budget when
`ST_GEOMETRY_PERF_STRICT=1` (CI runners are not reference devices). See
`PERFORMANCE.md` for the recorded baseline and method.
