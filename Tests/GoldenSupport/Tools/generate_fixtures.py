#!/usr/bin/env python3
"""Generate the deterministic synthetic fixtures for WP-04.

This is a *developer* tool; it is not part of the build and CI does not run it.
It requires Pillow (``pip install pillow`` or the DSH bundled Python).

Single source of truth
----------------------
Run this script to regenerate, in one pass:

* ``Fixtures/manifest.json``          – the fixture catalog (checked in)
* ``Fixtures/reference/*.png``        – 8-bit sRGB RGBA reference images (checked in)
* ``Tests/GoldenSupport/Sources/GoldenSupport/FixtureCatalogData.swift``
                                      – the same catalog as Swift data (checked in)

``FixtureSelfCheckTests`` fails when the committed files drift from the Swift
catalog, when a reference image hash changes, or when a reference image no
longer satisfies its structural probes.

Determinism
-----------
Every pattern is rendered with integer arithmetic only (plus symmetric
floating-point ellipse tests for the face outline), so the same input always
produces byte-identical pixels and, with the same Pillow version, byte-identical
PNGs.  No real photographs, no network access, no randomness beyond SplitMix64.

Usage
-----
    python Tests/GoldenSupport/Tools/generate_fixtures.py
"""

from __future__ import annotations

import hashlib
import json
import math
import re
import sys
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[3]
FIXTURES_DIR = REPO_ROOT / "Fixtures"
REFERENCE_DIR = FIXTURES_DIR / "reference"
CATALOG_SWIFT = (
    REPO_ROOT
    / "Tests"
    / "GoldenSupport"
    / "Sources"
    / "GoldenSupport"
    / "FixtureCatalogData.swift"
)
# The confined worktree sandbox cannot write below Tests/; this file is emitted
# next to the fixtures and copied into place with the editor. It is deleted by
# the generator's verification pass.
STAGING_SWIFT = FIXTURES_DIR / ".build" / "FixtureCatalogData.swift"

SCHEMA_VERSION = 1
GENERATOR_VERSION = "1.0.0"
GENERATED_BY = "Tests/GoldenSupport/Tools/generate_fixtures.py"

MASK64 = (1 << 64) - 1


# --------------------------------------------------------------------------- #
# Colors
# --------------------------------------------------------------------------- #


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    text = value.removeprefix("#")
    if len(text) != 6:
        raise ValueError(f"invalid color: {value!r}")
    return tuple(int(text[index : index + 2], 16) for index in (0, 2, 4))  # type: ignore[return-value]


def rgb_to_hex(rgb: tuple[int, int, int]) -> str:
    return "#%02X%02X%02X" % rgb


# --------------------------------------------------------------------------- #
# Deterministic PRNG (identical algorithm in Swift: SplitMix64)
# --------------------------------------------------------------------------- #


class SplitMix64:
    def __init__(self, seed: int) -> None:
        self.state = seed & MASK64

    def next(self) -> int:
        self.state = (self.state + 0x9E3779B97F4A7C15) & MASK64
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK64
        return (z ^ (z >> 31)) & MASK64


# --------------------------------------------------------------------------- #
# Raster helpers
# --------------------------------------------------------------------------- #


class Raster:
    def __init__(self, width: int, height: int, background: tuple[int, int, int]) -> None:
        self.width = width
        self.height = height
        self.pixels = bytearray(width * height * 4)
        self.fill_rect(0, 0, width, height, background)

    def set_pixel(self, x: int, y: int, color: tuple[int, int, int], alpha: int = 255) -> None:
        if x < 0 or y < 0 or x >= self.width or y >= self.height:
            return
        offset = (y * self.width + x) * 4
        self.pixels[offset] = color[0]
        self.pixels[offset + 1] = color[1]
        self.pixels[offset + 2] = color[2]
        self.pixels[offset + 3] = alpha

    def fill_rect(self, x: int, y: int, width: int, height: int, color: tuple[int, int, int]) -> None:
        x0 = max(0, x)
        y0 = max(0, y)
        x1 = min(self.width, x + width)
        y1 = min(self.height, y + height)
        if x0 >= x1 or y0 >= y1:
            return
        row = bytes(color) + b"\xff" * 1
        for yy in range(y0, y1):
            start = (yy * self.width + x0) * 4
            end = (yy * self.width + x1) * 4
            self.pixels[start:end] = row * (x1 - x0)

    def fill_ellipse(
        self,
        center_x: float,
        center_y: float,
        radius_x: float,
        radius_y: float,
        color: tuple[int, int, int],
    ) -> None:
        if radius_x <= 0 or radius_y <= 0:
            return
        min_x = max(0, math.floor(center_x - radius_x))
        max_x = min(self.width - 1, math.ceil(center_x + radius_x))
        min_y = max(0, math.floor(center_y - radius_y))
        max_y = min(self.height - 1, math.ceil(center_y + radius_y))
        for y in range(min_y, max_y + 1):
            dy = ((y + 0.5) - center_y) / radius_y
            for x in range(min_x, max_x + 1):
                dx = ((x + 0.5) - center_x) / radius_x
                if dx * dx + dy * dy <= 1.0:
                    self.set_pixel(x, y, color)

    def fill_centered_rect(
        self,
        center_x: float,
        half_width: float,
        y0: int,
        y1: int,
        color: tuple[int, int, int],
    ) -> None:
        left = round_half_up(center_x - half_width)
        right = self.width - left
        self.fill_rect(left, y0, right - left, y1 - y0, color)

    def mirror(self) -> bool:
        return is_mirror_symmetric(self.width, self.height, self.pixels)


def is_mirror_symmetric(width: int, height: int, pixels: bytes | bytearray) -> bool:
    for y in range(height):
        row = y * width
        for x in range(width // 2):
            left = (row + x) * 4
            right = (row + (width - 1 - x)) * 4
            if pixels[left : left + 4] != pixels[right : right + 4]:
                return False
    return True


def round_half_up(value: float) -> int:
    return int(math.floor(value + 0.5))


# --------------------------------------------------------------------------- #
# Pattern renderers
# --------------------------------------------------------------------------- #


def gradient_channel(start: int, end: int, index: int, count: int) -> int:
    if count <= 1:
        return start
    numerator = start * (count - 1 - index) + end * index + (count - 1) // 2
    return numerator // (count - 1)


def render_solid(entry: dict) -> bytes:
    color = hex_to_rgb(entry["colors"][0])
    raster = Raster(entry["width"], entry["height"], color)
    return bytes(raster.pixels)


def render_gradient(entry: dict) -> bytes:
    width, height = entry["width"], entry["height"]
    start = hex_to_rgb(entry["colors"][0])
    end = hex_to_rgb(entry["colors"][1])
    axis = entry["axis"]
    raster = Raster(width, height, start)
    if axis == "horizontal":
        for x in range(width):
            color = tuple(gradient_channel(start[c], end[c], x, width) for c in range(3))
            for y in range(height):
                raster.set_pixel(x, y, color)
    elif axis == "vertical":
        for y in range(height):
            color = tuple(gradient_channel(start[c], end[c], y, height) for c in range(3))
            for x in range(width):
                raster.set_pixel(x, y, color)
    else:
        raise ValueError(f"unknown gradient axis: {axis!r}")
    return bytes(raster.pixels)


def render_checkerboard(entry: dict) -> bytes:
    width, height = entry["width"], entry["height"]
    light = hex_to_rgb(entry["colors"][0])
    dark = hex_to_rgb(entry["colors"][1])
    cell = entry["cellSize"]
    raster = Raster(width, height, light)
    for y in range(height):
        for x in range(width):
            if ((x // cell) + (y // cell)) % 2 == 1:
                raster.set_pixel(x, y, dark)
    return bytes(raster.pixels)


def color_chart_geometry(entry: dict) -> tuple[int, int, int, int]:
    width, height = entry["width"], entry["height"]
    columns = entry["columns"]
    rows = math.ceil(len(entry["colors"]) / columns)
    margin, gap = 10, 6
    patch_width = (width - 2 * margin - (columns - 1) * gap) // columns
    patch_height = (height - 2 * margin - (rows - 1) * gap) // rows
    if patch_width <= 0 or patch_height <= 0:
        raise ValueError(f"fixture {entry['id']}: color chart does not fit")
    return columns, rows, patch_width, patch_height


def render_color_chart(entry: dict) -> bytes:
    width, height = entry["width"], entry["height"]
    columns, rows, patch_width, patch_height = color_chart_geometry(entry)
    raster = Raster(width, height, (128, 128, 128))
    gap = 6
    margin = 10
    for index, hex_value in enumerate(entry["colors"]):
        row, column = divmod(index, columns)
        x = margin + column * (patch_width + gap)
        y = margin + row * (patch_height + gap)
        raster.fill_rect(x, y, patch_width, patch_height, hex_to_rgb(hex_value))
    return bytes(raster.pixels)


def render_noise(entry: dict) -> bytes:
    width, height = entry["width"], entry["height"]
    base = hex_to_rgb(entry["colors"][0])
    amplitude = entry["amplitude"]
    span = 2 * amplitude + 1
    rng = SplitMix64(entry["seed"])
    raster = Raster(width, height, base)
    for y in range(height):
        for x in range(width):
            color = tuple(
                max(0, min(255, base[channel] + (rng.next() % span) - amplitude))
                for channel in range(3)
            )
            raster.set_pixel(x, y, color)
    return bytes(raster.pixels)


def render_vertical_edge(entry: dict) -> bytes:
    width, height = entry["width"], entry["height"]
    left = hex_to_rgb(entry["colors"][0])
    right = hex_to_rgb(entry["colors"][1])
    edge = entry["edgeX"]
    raster = Raster(width, height, right)
    raster.fill_rect(0, 0, edge, height, left)
    return bytes(raster.pixels)


def render_grid(entry: dict) -> bytes:
    width, height = entry["width"], entry["height"]
    background = hex_to_rgb(entry["colors"][0])
    line = hex_to_rgb(entry["colors"][1])
    spacing = entry["spacing"]
    line_width = entry["lineWidth"]
    raster = Raster(width, height, background)
    for y in range(height):
        for x in range(width):
            if x % spacing < line_width or y % spacing < line_width:
                raster.set_pixel(x, y, line)
    return bytes(raster.pixels)


def render_face_silhouette(entry: dict) -> bytes:
    """A deliberately crude, symmetric face outline – not a person."""
    width, height = entry["width"], entry["height"]
    skin, hair, background, eye, lips, shirt = (
        hex_to_rgb(value) for value in entry["colors"]
    )
    raster = Raster(width, height, background)
    center_x = width / 2.0

    # Hair, then neck and torso, then the face on top.
    raster.fill_ellipse(center_x, 0.40 * height, 0.30 * width, 0.30 * height, hair)
    raster.fill_centered_rect(
        center_x, 0.08 * width, round_half_up(0.62 * height), round_half_up(0.80 * height), skin
    )
    raster.fill_centered_rect(
        center_x, 0.50 * width, round_half_up(0.78 * height), height, shirt
    )
    raster.fill_ellipse(center_x, 0.42 * height, 0.24 * width, 0.27 * height, skin)

    eye_dx = 0.095 * width
    eye_y = 0.40 * height
    eye_rx = 0.045 * width
    eye_ry = 0.025 * height
    raster.fill_ellipse(center_x - eye_dx, eye_y, eye_rx, eye_ry, eye)
    raster.fill_ellipse(center_x + eye_dx, eye_y, eye_rx, eye_ry, eye)

    brow_y0 = round_half_up(0.345 * height)
    brow_height = max(2, round_half_up(0.014 * height))
    brow_half = 0.05 * width
    raster.fill_rect(
        round_half_up(center_x - eye_dx - brow_half),
        brow_y0,
        round_half_up(2 * brow_half),
        brow_height,
        hair,
    )
    raster.fill_rect(
        round_half_up(center_x + eye_dx - brow_half),
        brow_y0,
        round_half_up(2 * brow_half),
        brow_height,
        hair,
    )

    raster.fill_ellipse(center_x, 0.545 * height, 0.075 * width, 0.022 * height, lips)
    return bytes(raster.pixels)


RENDERERS = {
    "solidColor": render_solid,
    "linearGradient": render_gradient,
    "checkerboard": render_checkerboard,
    "colorChart": render_color_chart,
    "noise": render_noise,
    "verticalEdge": render_vertical_edge,
    "grid": render_grid,
    "faceSilhouette": render_face_silhouette,
}

# --------------------------------------------------------------------------- #
# Fixtures
# --------------------------------------------------------------------------- #

MACBETH_24 = [
    "#735246",  # 1  dark skin
    "#C29682",  # 2  light skin
    "#627A9D",  # 3  blue sky
    "#576C43",  # 4  foliage
    "#8580B1",  # 5  blue flower
    "#67BDAA",  # 6  bluish green
    "#D67E2C",  # 7  orange
    "#505BA6",  # 8  purplish blue
    "#C15A63",  # 9  moderate red
    "#5E3C6C",  # 10 purple
    "#9DBC40",  # 11 yellow green
    "#E0A32E",  # 12 orange yellow
    "#383D96",  # 13 blue
    "#469449",  # 14 green
    "#AF363C",  # 15 red
    "#E7C71F",  # 16 yellow
    "#BB5695",  # 17 magenta
    "#0885A1",  # 18 cyan
    "#F3F3F2",  # 19 white
    "#C8C8C8",  # 20 neutral 8
    "#A0A0A0",  # 21 neutral 6.5
    "#7A7A79",  # 22 neutral 5
    "#555555",  # 23 neutral 3.5
    "#343434",  # 24 black
]

SKIN_TONES = [
    "#F6D7C3",  # very light
    "#E8B98F",  # light
    "#C68B59",  # medium
    "#A9714B",  # olive
    "#7B4B2A",  # brown
    "#4A2C1D",  # deep
]

FIXTURES: list[dict] = [
    {
        "id": "solid.cream",
        "kind": "solidColor",
        "width": 64,
        "height": 64,
        "seed": 0,
        "colors": ["#E8D5C4"],
        "purpose": "Flat opaque warm patch for alpha, colour and ICC round-trips.",
    },
    {
        "id": "gradient.gray-horizontal",
        "kind": "linearGradient",
        "width": 256,
        "height": 64,
        "seed": 0,
        "colors": ["#000000", "#FFFFFF"],
        "axis": "horizontal",
        "purpose": "Monotonic black-to-white horizontal ramp for tone curve checks.",
    },
    {
        "id": "gradient.warm-vertical",
        "kind": "linearGradient",
        "width": 192,
        "height": 128,
        "seed": 0,
        "colors": ["#F6D7C3", "#402A2A"],
        "axis": "vertical",
        "purpose": "Warm skin-ish vertical ramp for white balance and banding checks.",
    },
    {
        "id": "checkerboard.8px",
        "kind": "checkerboard",
        "width": 128,
        "height": 96,
        "seed": 0,
        "colors": ["#FFFFFF", "#202020"],
        "cellSize": 8,
        "purpose": "High frequency alignment target for warp and sampling code.",
    },
    {
        "id": "colorchart.macbeth24",
        "kind": "colorChart",
        "width": 240,
        "height": 160,
        "seed": 0,
        "colors": MACBETH_24,
        "columns": 6,
        "purpose": "24 patch colour chart for colour pipeline and ΔE00 thresholds.",
    },
    {
        "id": "colorchart.skintones",
        "kind": "colorChart",
        "width": 180,
        "height": 120,
        "seed": 0,
        "colors": SKIN_TONES,
        "columns": 3,
        "purpose": "Six skin tone swatches (I–VI) for retouch and evenness safety tests.",
    },
    {
        "id": "noise.midgray",
        "kind": "noise",
        "width": 128,
        "height": 128,
        "seed": 20261024,
        "colors": ["#808080"],
        "amplitude": 28,
        "purpose": "Deterministic grain around mid-grey for denoise and grain checks.",
    },
    {
        "id": "edge.vertical",
        "kind": "verticalEdge",
        "width": 160,
        "height": 120,
        "seed": 0,
        "colors": ["#1E1E1E", "#F2F2F2"],
        "edgeX": 80,
        "purpose": "Straight vertical edge for geometry boundary and background checks.",
    },
    {
        "id": "grid.tiles",
        "kind": "grid",
        "width": 192,
        "height": 144,
        "seed": 0,
        "colors": ["#F5F5F5", "#303030"],
        "spacing": 24,
        "lineWidth": 2,
        "purpose": "Tile grid with straight lines for background protection tests.",
    },
    {
        "id": "face.silhouette",
        "kind": "faceSilhouette",
        "width": 192,
        "height": 256,
        "seed": 0,
        "colors": ["#D9A066", "#2B2118", "#2F4F6F", "#2A1A12", "#B5654F", "#5B6470"],
        "purpose": "Symmetric cartoon face outline; never a real person or photo.",
    },
]


# --------------------------------------------------------------------------- #
# Structural probes (mirrored by FixtureSelfCheckTests)
# --------------------------------------------------------------------------- #


def probe_expectations(entry: dict) -> list[tuple[int, int, str]]:
    """Return (x, y, hex) probes that both generated and reference images honour."""
    width, height = entry["width"], entry["height"]
    kind = entry["kind"]
    if kind == "solidColor":
        color = entry["colors"][0]
        return [(0, 0, color), (width - 1, height - 1, color), (width // 2, height // 2, color)]
    if kind == "linearGradient":
        from_color, to_color = entry["colors"]
        if entry["axis"] == "horizontal":
            return [(0, height // 2, from_color), (width - 1, height // 2, to_color)]
        return [(width // 2, 0, from_color), (width // 2, height - 1, to_color)]
    if kind == "checkerboard":
        light, dark = entry["colors"]
        cell = entry["cellSize"]
        return [
            (0, 0, light),
            (cell, 0, dark),
            (0, cell, dark),
            (cell, cell, light),
        ]
    if kind == "colorChart":
        columns, rows, patch_width, patch_height = color_chart_geometry(entry)
        probes = [(0, 0, "#808080")]
        for index, color in enumerate(entry["colors"]):
            row, column = divmod(index, columns)
            x = 10 + column * (patch_width + 6) + patch_width // 2
            y = 10 + row * (patch_height + 6) + patch_height // 2
            probes.append((x, y, color))
        return probes
    if kind == "noise":
        return []
    if kind == "verticalEdge":
        left, right = entry["colors"]
        edge = entry["edgeX"]
        return [(0, height // 2, left), (edge - 1, height // 2, left), (edge, height // 2, right)]
    if kind == "grid":
        background, line = entry["colors"]
        spacing, line_width = entry["spacing"], entry["lineWidth"]
        return [
            (0, 0, line),
            (spacing, 0, line),
            (spacing // 2 + line_width, spacing // 2 + line_width, background),
        ]
    if kind == "faceSilhouette":
        skin, _hair, background, eye, lips, shirt = entry["colors"]
        return [
            (2, 2, background),
            (width // 2, round_half_up(0.22 * height), skin),
            (round_half_up(width / 2 - 0.095 * width), round_half_up(0.40 * height), eye),
            (width // 2, round_half_up(0.545 * height), lips),
            (width // 2, height - 4, shirt),
        ]
    raise ValueError(f"no probes for kind {kind!r}")


def check_invariants(entry: dict, pixels: bytes) -> None:
    width, height = entry["width"], entry["height"]
    assert len(pixels) == width * height * 4, entry["id"]
    kind = entry["kind"]

    for x, y, expected in probe_expectations(entry):
        offset = (y * width + x) * 4
        actual = rgb_to_hex(tuple(pixels[offset : offset + 3]))  # type: ignore[arg-type]
        if actual != expected:
            raise AssertionError(
                f"{entry['id']}: probe ({x},{y}) expected {expected}, got {actual}"
            )

    if kind == "noise":
        base = hex_to_rgb(entry["colors"][0])
        amplitude = entry["amplitude"]
        total = [0, 0, 0]
        minimum = [255, 255, 255]
        maximum = [0, 0, 0]
        for offset in range(0, len(pixels), 4):
            for channel in range(3):
                value = pixels[offset + channel]
                total[channel] += value
                minimum[channel] = min(minimum[channel], value)
                maximum[channel] = max(maximum[channel], value)
        count = width * height
        for channel in range(3):
            mean = total[channel] / count
            if abs(mean - base[channel]) > 2.0:
                raise AssertionError(f"{entry['id']}: channel mean {mean:.2f} drifted")
            if minimum[channel] < base[channel] - amplitude:
                raise AssertionError(f"{entry['id']}: value below amplitude range")
            if maximum[channel] > base[channel] + amplitude:
                raise AssertionError(f"{entry['id']}: value above amplitude range")

    if kind == "faceSilhouette":
        if not is_mirror_symmetric(width, height, pixels):
            raise AssertionError(f"{entry['id']}: face silhouette is not mirror symmetric")

    if kind == "grid":
        spacing, line_width = entry["spacing"], entry["lineWidth"]
        background, line = entry["colors"]
        for x in range(width):
            for y in range(height):
                expected = line if (x % spacing < line_width or y % spacing < line_width) else background
                offset = (y * width + x) * 4
                actual = rgb_to_hex(tuple(pixels[offset : offset + 3]))  # type: ignore[arg-type]
                if actual != expected:
                    raise AssertionError(f"{entry['id']}: grid mismatch at ({x},{y})")


# --------------------------------------------------------------------------- #
# Emit
# --------------------------------------------------------------------------- #


def swift_string(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def swift_literal(entry: dict) -> str:
    arguments = [
        f"id: {swift_string(entry['id'])}",
        f"kind: .{entry['kind']}",
        f"width: {entry['width']}",
        f"height: {entry['height']}",
        f"seed: {entry['seed']}",
        f"colors: [{', '.join(swift_string(color) for color in entry['colors'])}]",
    ]
    for key in ("axis", "cellSize", "spacing", "lineWidth", "edgeX", "columns", "amplitude"):
        if key in entry:
            value = entry[key]
            if key == "axis":
                arguments.append(f"axis: .{value}")
            else:
                arguments.append(f"{key}: {value}")
    arguments.append(f"purpose: {swift_string(entry['purpose'])}")
    arguments.append(f"referenceFile: {swift_string(entry['referenceFile'])}")
    arguments.append(f"referenceSHA256: {swift_string(entry['referenceSHA256'])}")
    return "        FixtureManifestEntry(" + ", ".join(arguments) + "),"


def emit_swift(entries: list[dict]) -> str:
    lines = [
        "// Generated by Tests/GoldenSupport/Tools/generate_fixtures.py.",
        "// Do not edit by hand: change the Python catalog and regenerate.",
        "// FixtureSelfCheckTests fails when this file, Fixtures/manifest.json and",
        "// the committed reference PNGs disagree.",
        "",
        "enum FixtureCatalogData {",
        "    static let entries: [FixtureManifestEntry] = [",
    ]
    lines.extend(swift_literal(entry) for entry in entries)
    lines.extend(["    ]", "}", ""])
    return "\n".join(lines)


def write_fixtures() -> None:
    REFERENCE_DIR.mkdir(parents=True, exist_ok=True)
    STAGING_SWIFT.parent.mkdir(parents=True, exist_ok=True)

    written: set[Path] = set()
    for entry in FIXTURES:
        renderer = RENDERERS[entry["kind"]]
        pixels = renderer(entry)
        check_invariants(entry, pixels)

        slug = entry["id"].replace(".", "-")
        file_name = f"{slug}.png"
        path = REFERENCE_DIR / file_name
        image = Image.frombytes("RGBA", (entry["width"], entry["height"]), pixels)
        image.save(path, format="PNG", optimize=False)
        written.add(path)

        data = path.read_bytes()
        entry["referenceFile"] = file_name
        entry["referenceSHA256"] = hashlib.sha256(data).hexdigest()

    for stale in REFERENCE_DIR.glob("*.png"):
        if stale not in written:
            stale.unlink()

    manifest = {
        "schemaVersion": SCHEMA_VERSION,
        "generatorVersion": GENERATOR_VERSION,
        "generatedBy": GENERATED_BY,
        "referenceDirectory": "reference",
        "fixtures": FIXTURES,
    }
    (FIXTURES_DIR / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    STAGING_SWIFT.write_text(emit_swift(FIXTURES), encoding="utf-8")

    total_bytes = sum((REFERENCE_DIR / entry["referenceFile"]).stat().st_size for entry in FIXTURES)
    print(f"Wrote {len(FIXTURES)} fixtures, {total_bytes} bytes of reference PNGs")
    for entry in FIXTURES:
        print(f"  {entry['id']:<28} {entry['kind']:<16} {entry['width']}x{entry['height']}")
    print(f"Swift catalog staged at {STAGING_SWIFT.relative_to(REPO_ROOT)}")


ARGUMENT_PATTERN = re.compile(r'(\w+):\s*(\[[^\]]*\]|"(?:[^"\\]|\\.)*"|\.\w+|-?\d+)')


def parse_swift_catalog(text: str) -> list[dict]:
    entries: list[dict] = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped.startswith("FixtureManifestEntry(") or not stripped.endswith("),"):
            continue
        body = stripped[len("FixtureManifestEntry(") : -2]
        entry: dict = {}
        for key, raw in ARGUMENT_PATTERN.findall(body):
            raw = raw.strip()
            if raw.startswith("["):
                entry[key] = re.findall(r'"([^"]*)"', raw)
            elif raw.startswith('"'):
                entry[key] = raw[1:-1]
            elif raw.startswith("."):
                entry[key] = raw[1:]
            else:
                entry[key] = int(raw)
        entries.append(entry)
    return entries


def verify() -> None:
    """Verify the committed manifest, reference images and Swift catalog agree."""
    problems: list[str] = []

    manifest_path = FIXTURES_DIR / "manifest.json"
    if not manifest_path.exists():
        raise SystemExit(f"missing {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schemaVersion") != SCHEMA_VERSION:
        problems.append("manifest schemaVersion changed")
    if manifest.get("generatorVersion") != GENERATOR_VERSION:
        problems.append("manifest generatorVersion changed")

    committed = manifest.get("fixtures", [])
    by_id = {entry["id"]: entry for entry in FIXTURES}
    base_entries: list[dict] = []
    for actual in committed:
        base = {key: value for key, value in actual.items() if key in by_id.get(actual["id"], {})}
        base_entries.append(base)
        expected = by_id.get(actual["id"])
        if expected is None:
            problems.append(f"unexpected fixture in manifest: {actual['id']}")
        elif base != expected:
            problems.append(f"manifest drift for {actual['id']}")
        for required in ("referenceFile", "referenceSHA256"):
            if required not in actual:
                problems.append(f"{actual['id']}: manifest is missing {required}")
    if len(committed) != len(FIXTURES):
        problems.append(f"manifest has {len(committed)} fixtures, expected {len(FIXTURES)}")

    if not CATALOG_SWIFT.exists():
        problems.append(f"missing {CATALOG_SWIFT}")
    else:
        swift_entries = parse_swift_catalog(CATALOG_SWIFT.read_text(encoding="utf-8"))
        if len(swift_entries) != len(FIXTURES):
            problems.append(
                f"Swift catalog has {len(swift_entries)} entries, expected {len(FIXTURES)}"
            )
        for expected, actual in zip(base_entries, swift_entries):
            filtered_actual = {key: actual[key] for key in actual if key in expected}
            if filtered_actual != expected:
                problems.append(f"Swift catalog entry drift for {expected['id']}")

    for entry in committed:
        path = REFERENCE_DIR / entry["referenceFile"]
        if not path.exists():
            problems.append(f"missing reference image for {entry['id']}")
            continue
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != entry["referenceSHA256"]:
            problems.append(f"{entry['id']}: reference SHA-256 changed")
        image = Image.open(path).convert("RGBA")
        if image.size != (entry["width"], entry["height"]):
            problems.append(f"{entry['id']}: reference size {image.size}")
            continue
        check_invariants(entry, image.tobytes())

    if problems:
        print("Fixture verification FAILED:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        raise SystemExit(1)
    print(f"Fixture verification passed for {len(committed)} fixtures")


def main() -> None:
    if "--verify" in sys.argv:
        verify()
    else:
        write_fixtures()


if __name__ == "__main__":
    main()
