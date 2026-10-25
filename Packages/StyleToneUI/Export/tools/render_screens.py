"""Render design-level screenshots for WP-19 (export / photo library / share).

These are token-faithful mockups, not simulator screenshots: this workspace is
Windows and has no Xcode/simulator. They mirror the SwiftUI source and the
English development copy in ExportCopy; regenerate with:

    python Packages/StyleToneUI/Export/tools/render_screens.py
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "screenshots"
OUT.mkdir(parents=True, exist_ok=True)

# Design tokens (StyleToneUI/DesignSystem/Tokens).
BACKGROUND = "#0C0D10"
SURFACE = "#14161A"
ELEVATED = "#1C1F25"
PRESSED = "#272B33"
PHOTO_BG = "#2E2E2E"
TEXT = "#F4F5F7"
TEXT_SECONDARY = "#B6BBC5"
TEXT_TERTIARY = "#8A919D"
ACCENT = "#DFA76C"
ACCENT_PRESSED = "#C58C50"
ON_ACCENT = "#14161A"
BORDER = "#2A2F37"
BORDER_STRONG = "#3E4550"
SUCCESS = "#5BD6A2"
WARNING = "#F2C66D"
ERROR = "#FF8A8A"
DISABLED = "#22262D"
ON_DISABLED = "#9AA1AC"

FONT_DIR = Path("C:/Windows/Fonts")
REGULAR = FONT_DIR / "segoeui.ttf"
BOLD = FONT_DIR / "segoeuib.ttf"
SEMI = FONT_DIR / "segoeuisb.ttf"
SEMI = SEMI if SEMI.exists() else BOLD


def font(size: int, weight: str = "regular") -> ImageFont.FreeTypeFont:
    path = {"regular": REGULAR, "semibold": SEMI, "bold": BOLD}[weight]
    return ImageFont.truetype(str(path), size)


def rounded(draw: ImageDraw.ImageDraw, box, radius: int, fill: str, outline: str | None = None, width: int = 2):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def wrapped_lines(text: str, fnt: ImageFont.FreeTypeFont, max_width: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if fnt.getlength(candidate) <= max_width:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def draw_text(
    draw: ImageDraw.ImageDraw,
    xy,
    text: str,
    fnt: ImageFont.FreeTypeFont,
    fill: str,
    max_width: int | None = None,
    line_gap: int = 8,
):
    x, y = xy
    lines = wrapped_lines(text, fnt, max_width) if max_width else [text]
    for line in lines:
        draw.text((x, y), line, font=fnt, fill=fill)
        y += fnt.size + line_gap
    return y


def make_photo(width: int, height: int) -> Image.Image:
    ys = np.linspace(0.0, 1.0, height, dtype=np.float32)[:, None]
    xs = np.linspace(0.0, 1.0, width, dtype=np.float32)[None, :]
    base = np.zeros((height, width, 3), dtype=np.float32)
    base[..., 0] = 0.62 + 0.25 * (1 - ys) + 0.06 * xs
    base[..., 1] = 0.42 + 0.18 * (1 - ys) + 0.04 * xs
    base[..., 2] = 0.34 + 0.20 * (1 - ys) + 0.10 * xs
    vignette = np.clip(1.0 - 0.55 * ((xs - 0.5) ** 2 + (ys - 0.5) ** 2) * 2.2, 0.45, 1.0)
    base *= vignette[..., None]
    stripes = ((np.arange(width) // 26) % 2).astype(np.float32)[None, :, None]
    base *= 0.94 + 0.06 * stripes
    arr = np.clip(base * 255, 0, 255).astype(np.uint8)
    image = Image.fromarray(arr, "RGB")
    # A soft portrait-like ellipse for visual focus.
    overlay = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.ellipse(
        (width * 0.33, height * 0.18, width * 0.67, height * 0.74),
        fill=(236, 190, 160, 90),
    )
    od.ellipse(
        (width * 0.38, height * 0.10, width * 0.62, height * 0.44),
        fill=(244, 205, 176, 110),
    )
    return Image.alpha_composite(image.convert("RGBA"), overlay).convert("RGB")


def paste_rounded(canvas: Image.Image, image: Image.Image, box, radius: int):
    x0, y0, x1, y1 = box
    size = (x1 - x0, y1 - y0)
    resized = image.resize(size, Image.LANCZOS)
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    canvas.paste(resized, (x0, y0), mask)


def render_panel() -> Image.Image:
    scale = 2
    width, height = 390 * scale, 844 * scale
    canvas = Image.new("RGB", (width, height), BACKGROUND)
    draw = ImageDraw.Draw(canvas)

    margin = 20 * scale
    # Status bar.
    draw.text((margin + 4 * scale, 14 * scale), "9:41", font=font(15 * scale, "semibold"), fill=TEXT)
    draw.rounded_rectangle(
        (width - margin - 24 * scale, 16 * scale, width - margin, 27 * scale),
        radius=5 * scale,
        fill=TEXT_SECONDARY,
    )

    # Header.
    y = 58 * scale
    draw.text((margin, y), "Export", font=font(28 * scale, "semibold"), fill=TEXT)
    draw_text(
        draw,
        (margin, y + 38 * scale),
        "Full resolution, ready for Photos or sharing.",
        font(14 * scale),
        TEXT_SECONDARY,
        max_width=width - 2 * margin - 34 * scale,
        line_gap=3 * scale,
    )
    # Close glyph.
    cx, cy = width - margin - 12 * scale, y + 14 * scale
    radius = 8 * scale
    draw.line((cx - radius, cy - radius, cx + radius, cy + radius), fill=TEXT_SECONDARY, width=3 * scale)
    draw.line((cx - radius, cy + radius, cx + radius, cy - radius), fill=TEXT_SECONDARY, width=3 * scale)

    # Preview.
    preview = (margin, 134 * scale, width - margin, 424 * scale)
    paste_rounded(canvas, make_photo(700, 525), preview, 16 * scale)
    draw.rounded_rectangle(preview, radius=16 * scale, outline=BORDER, width=2 * scale)

    # Metadata.
    y = 436 * scale
    draw.text((margin, y), "4032 × 3024", font=font(13 * scale), fill=TEXT_SECONDARY)
    draw.text((margin + 118 * scale, y), "12.2 MP", font=font(13 * scale), fill=TEXT_TERTIARY)
    # Location row.
    y += 26 * scale
    draw.ellipse((margin + 2 * scale, y + 4 * scale, margin + 10 * scale, y + 12 * scale), outline=TEXT_TERTIARY, width=2 * scale)
    draw.line((margin + 2 * scale, y + 8 * scale, margin + 10 * scale, y + 8 * scale), fill=BACKGROUND, width=2 * scale)
    draw.text((margin + 18 * scale, y), "Location metadata removed", font=font(12 * scale), fill=TEXT_TERTIARY)

    # Format section.
    y = 486 * scale
    draw.text((margin, y), "Format", font=font(16 * scale, "semibold"), fill=TEXT)
    y += 26 * scale
    draw.text((margin, y), "File format", font=font(11 * scale), fill=TEXT_SECONDARY)
    y += 18 * scale
    seg = (margin, y, width - margin, y + 34 * scale)
    rounded(draw, seg, 8 * scale, SURFACE, BORDER, 2 * scale)
    half = (seg[2] - seg[0]) // 2
    rounded(draw, (seg[0], seg[1], seg[0] + half, seg[3]), 8 * scale, ELEVATED)
    draw.text(
        (seg[0] + half // 2 - 20 * scale, y + 8 * scale),
        "HEIC",
        font=font(13 * scale, "semibold"),
        fill=TEXT,
    )
    draw.text(
        (seg[0] + half + half // 2 - 18 * scale, y + 8 * scale),
        "JPEG",
        font=font(13 * scale),
        fill=TEXT_SECONDARY,
    )
    y += 42 * scale
    draw_text(
        draw,
        (margin, y),
        "HEIC keeps more detail at a smaller size. JPEG opens everywhere.",
        font(11 * scale),
        TEXT_TERTIARY,
        max_width=width - 2 * margin,
        line_gap=2 * scale,
    )

    # Quality row.
    y += 42 * scale
    draw.text((margin, y), "Quality", font=font(11 * scale), fill=TEXT_SECONDARY)
    rounded(draw, (width - margin - 110 * scale, y - 8 * scale, width - margin, y + 22 * scale), 8 * scale, SURFACE, BORDER, 2 * scale)
    draw.text((width - margin - 96 * scale, y - 2 * scale), "High", font=font(12 * scale), fill=TEXT)
    qx = width - margin - 30 * scale
    qy = y + 3 * scale
    draw.line((qx - 5 * scale, qy, qx, qy + 5 * scale), fill=TEXT_SECONDARY, width=2 * scale)
    draw.line((qx, qy + 5 * scale, qx + 5 * scale, qy), fill=TEXT_SECONDARY, width=2 * scale)

    # Primary action.
    y = 668 * scale
    rounded(draw, (margin, y, width - margin, y + 46 * scale), 12 * scale, ACCENT)
    draw.text((margin + 24 * scale, y + 12 * scale), "Save to Photos", font=font(15 * scale, "semibold"), fill=ON_ACCENT)
    # Secondary action.
    y += 56 * scale
    rounded(draw, (margin, y, width - margin, y + 46 * scale), 12 * scale, ELEVATED, BORDER, 2 * scale)
    draw.text((margin + 24 * scale, y + 12 * scale), "Share…", font=font(15 * scale, "semibold"), fill=TEXT)
    draw.text((width - margin - 30 * scale, y + 12 * scale), "↗", font=font(14 * scale), fill=TEXT_SECONDARY)

    # Quota + footer.
    y += 58 * scale
    draw.text((margin, y), "3 free exports left", font=font(11 * scale), fill=TEXT_TERTIARY)
    y += 24 * scale
    draw_text(
        draw,
        (margin, y),
        "StyleTone only adds photos to your library. It never reads or uploads them.",
        font(10 * scale),
        TEXT_TERTIARY,
        max_width=width - 2 * margin,
        line_gap=2 * scale,
    )

    # Home indicator.
    draw.rounded_rectangle(
        (width // 2 - 60 * scale, height - 14 * scale, width // 2 + 60 * scale, height - 9 * scale),
        radius=3 * scale,
        fill=TEXT_TERTIARY,
    )
    return canvas


def render_permission_panel() -> Image.Image:
    scale = 2
    width, height = 390 * scale, 844 * scale
    canvas = Image.new("RGB", (width, height), BACKGROUND)
    draw = ImageDraw.Draw(canvas)
    margin = 20 * scale

    # Status bar.
    draw.text((margin + 4 * scale, 14 * scale), "9:41", font=font(15 * scale, "semibold"), fill=TEXT)
    draw.rounded_rectangle(
        (width - margin - 24 * scale, 16 * scale, width - margin, 27 * scale),
        radius=5 * scale,
        fill=TEXT_SECONDARY,
    )

    draw.text((margin, 58 * scale), "Export", font=font(28 * scale, "semibold"), fill=TEXT)
    draw_text(
        draw,
        (margin, 96 * scale),
        "Full resolution, ready for Photos or sharing.",
        font(14 * scale),
        TEXT_SECONDARY,
        max_width=width - 2 * margin,
        line_gap=3 * scale,
    )
    cx, cy = width - margin - 12 * scale, 72 * scale
    radius = 8 * scale
    draw.line((cx - radius, cy - radius, cx + radius, cy + radius), fill=TEXT_SECONDARY, width=3 * scale)
    draw.line((cx - radius, cy + radius, cx + radius, cy - radius), fill=TEXT_SECONDARY, width=3 * scale)

    preview = (margin, 150 * scale, width - margin, 368 * scale)
    paste_rounded(canvas, make_photo(700, 430), preview, 16 * scale)
    draw.rounded_rectangle(preview, radius=16 * scale, outline=BORDER, width=2 * scale)
    draw.text((margin, 380 * scale), "4032 × 3024", font=font(13 * scale), fill=TEXT_SECONDARY)
    draw.text((margin + 118 * scale, 380 * scale), "12.2 MP", font=font(13 * scale), fill=TEXT_TERTIARY)

    # Warning card with all three exits exposed by the SwiftUI card.
    card = (margin, 404 * scale, width - margin, 648 * scale)
    rounded(draw, card, 16 * scale, SURFACE, WARNING, 2 * scale)
    draw.text((margin + 16 * scale, 420 * scale), "Photos access is off", font=font(17 * scale, "semibold"), fill=TEXT)
    draw_text(
        draw,
        (margin + 16 * scale, 452 * scale),
        "Allow StyleTone to add photos in Settings, or share the photo instead.",
        font(12 * scale),
        TEXT_SECONDARY,
        max_width=width - 2 * margin - 32 * scale,
        line_gap=3 * scale,
    )
    rounded(draw, (margin + 16 * scale, 502 * scale, width - margin - 16 * scale, 534 * scale), 10 * scale, ELEVATED, BORDER, 2 * scale)
    draw.text((margin + 30 * scale, 509 * scale), "Open Settings", font=font(13 * scale, "semibold"), fill=TEXT)
    rounded(draw, (margin + 16 * scale, 542 * scale, width - margin - 16 * scale, 574 * scale), 10 * scale, ACCENT)
    draw.text((margin + 30 * scale, 549 * scale), "Share instead", font=font(13 * scale, "semibold"), fill=ON_ACCENT)
    rounded(draw, (margin + 16 * scale, 582 * scale, width - margin - 16 * scale, 614 * scale), 10 * scale, ELEVATED, BORDER, 2 * scale)
    draw.text((margin + 30 * scale, 589 * scale), "Check again", font=font(13 * scale, "semibold"), fill=TEXT)

    # Actions: save disabled, share enabled.
    y = 664 * scale
    rounded(draw, (margin, y, width - margin, y + 46 * scale), 12 * scale, DISABLED)
    draw.text((margin + 24 * scale, y + 12 * scale), "Save to Photos", font=font(15 * scale, "semibold"), fill=ON_DISABLED)
    y += 56 * scale
    rounded(draw, (margin, y, width - margin, y + 46 * scale), 12 * scale, ELEVATED, BORDER, 2 * scale)
    draw.text((margin + 24 * scale, y + 12 * scale), "Share…", font=font(15 * scale, "semibold"), fill=TEXT)
    y += 58 * scale
    draw.text((margin, y), "Nothing is counted when sharing is cancelled.", font=font(11 * scale), fill=TEXT_TERTIARY)
    y += 26 * scale
    draw_text(
        draw,
        (margin, y),
        "Only adds photos. Never reads or uploads.",
        font(10 * scale),
        TEXT_TERTIARY,
        max_width=width - 2 * margin,
        line_gap=2 * scale,
    )

    draw.rounded_rectangle(
        (width // 2 - 60 * scale, height - 14 * scale, width // 2 + 60 * scale, height - 9 * scale),
        radius=3 * scale,
        fill=TEXT_TERTIARY,
    )
    return canvas


def arrow(draw: ImageDraw.ImageDraw, start, end, color=TEXT_TERTIARY, width=3, label: str | None = None, label_font=None):
    draw.line((start, end), fill=color, width=width)
    angle = math.atan2(end[1] - start[1], end[0] - start[0])
    head = 14
    left = (end[0] - head * math.cos(angle - 0.4), end[1] - head * math.sin(angle - 0.4))
    right = (end[0] - head * math.cos(angle + 0.4), end[1] - head * math.sin(angle + 0.4))
    draw.polygon([end, left, right], fill=color)
    if label and label_font:
        mid = ((start[0] + end[0]) / 2, (start[1] + end[1]) / 2 - 24)
        draw.text(mid, label, font=label_font, fill=TEXT_TERTIARY, anchor="mm")


def polyline_arrow(draw: ImageDraw.ImageDraw, points, color=TEXT_TERTIARY, width=3):
    for start, end in zip(points, points[1:]):
        draw.line((start, end), fill=color, width=width)
    start, end = points[-2], points[-1]
    angle = math.atan2(end[1] - start[1], end[0] - start[0])
    head = 14
    left = (end[0] - head * math.cos(angle - 0.4), end[1] - head * math.sin(angle - 0.4))
    right = (end[0] - head * math.cos(angle + 0.4), end[1] - head * math.sin(angle + 0.4))
    draw.polygon([end, left, right], fill=color)


def render_flow() -> Image.Image:
    width, height = 1400, 980
    canvas = Image.new("RGB", (width, height), BACKGROUND)
    draw = ImageDraw.Draw(canvas)

    title_font = font(34, "semibold")
    sub_font = font(17)
    node_title = font(20, "semibold")
    node_body = font(15)
    small = font(14)

    draw.text((56, 46), "WP-19 · Export / Photos / Share", font=title_font, fill=TEXT)
    draw.text(
        (56, 92),
        "One full-resolution file, one destination, one count. Failures never consume a free export.",
        font=sub_font,
        fill=TEXT_SECONDARY,
    )

    def box(x0, y0, x1, y1, heading, lines, accent=BORDER_STRONG, fill=SURFACE):
        rounded(draw, (x0, y0, x1, y1), 18, fill, accent, 3)
        draw.text((x0 + 20, y0 + 16), heading, font=node_title, fill=TEXT)
        yy = y0 + 48
        for line in lines:
            for wrapped in wrapped_lines(line, node_body, x1 - x0 - 40):
                draw.text((x0 + 20, yy), wrapped, font=node_body, fill=TEXT_SECONDARY)
                yy += 22

    # Row 1.
    box(60, 160, 330, 270, "Editor · WP-17", ["Full-resolution RenderRequest", "+ optional preview"], ACCENT)
    box(390, 160, 680, 285, "Preflight", ["Entitlement (WP-20)", "Add-only access for Photos"], BORDER_STRONG)
    box(740, 160, 1030, 285, "Render · WP-17", ["ImageRendering.render", "verify pixelSize == expected"], ACCENT)
    box(1090, 160, 1340, 285, "Encode · WP-02", ["HEIC / JPEG", "verify file + format"], ACCENT)

    arrow(draw, (330, 215), (388, 215))
    arrow(draw, (680, 215), (738, 215))
    arrow(draw, (1030, 215), (1088, 215))

    # Row 2: destinations.
    box(740, 380, 1010, 495, "Save to Photos", ["PHAssetCreationRequest", "add-only, never read"], SUCCESS)
    box(1060, 380, 1340, 495, "System share", ["UIActivityViewController", "file URL only"], SUCCESS)
    arrow(draw, (1185, 285), (900, 378))
    arrow(draw, (1215, 285), (1200, 378))

    # Success.
    box(900, 620, 1340, 745, "Delivered", ["count once (save completed / share completed)", "delete staging file, show result"], SUCCESS)
    arrow(draw, (875, 495), (1000, 618), color=SUCCESS, label="system confirms", label_font=small)
    arrow(draw, (1200, 495), (1170, 618), color=SUCCESS, label="completed == true", label_font=small)

    # Exits.
    box(60, 380, 330, 510, "Permission exit", ["denied → Open Settings", "or Share instead"], WARNING)
    polyline_arrow(draw, [(470, 285), (360, 430), (332, 430)], color=WARNING)

    box(60, 560, 330, 695, "Failure / retry", ["render, encode, size, save", "retry; save-only retry reuses file"], ERROR)
    polyline_arrow(draw, [(800, 285), (420, 620), (332, 620)], color=ERROR)

    box(60, 745, 330, 870, "Cancel / close", ["delete file, no count", "save already handed off is not cancelled"], BORDER_STRONG)
    polyline_arrow(draw, [(330, 215), (350, 800), (332, 800)], color=TEXT_TERTIARY)

    # Bottom lifecycle note.
    rounded(draw, (450, 790, 1340, 900), 18, ELEVATED, BORDER, 2)
    draw.text((476, 812), "Temporary file lifecycle", font=node_title, fill=TEXT)
    draw.text(
        (476, 848),
        "<tmp>/StyleToneExports · deleted after success, failure, cancel or close · 10-minute stale sweep on next start",
        font=small,
        fill=TEXT_SECONDARY,
    )

    # Legend.
    legend_y = 930
    for x, color, label in [
        (60, ACCENT, "WP-17 render"),
        (250, SUCCESS, "delivered + counted"),
        (520, WARNING, "permission exit"),
        (740, ERROR, "retry"),
        (900, BORDER_STRONG, "state / cleanup"),
    ]:
        draw.rounded_rectangle((x, legend_y, x + 18, legend_y + 18), radius=5, fill=color)
        draw.text((x + 28, legend_y - 1), label, font=small, fill=TEXT_TERTIARY)

    return canvas


def main() -> None:
    render_panel().save(OUT / "01-panel.png", optimize=True)
    render_permission_panel().save(OUT / "02-permission.png", optimize=True)
    render_flow().save(OUT / "03-flow.png", optimize=True)
    print(f"wrote {OUT / '01-panel.png'}")
    print(f"wrote {OUT / '02-permission.png'}")
    print(f"wrote {OUT / '03-flow.png'}")


if __name__ == "__main__":
    main()
