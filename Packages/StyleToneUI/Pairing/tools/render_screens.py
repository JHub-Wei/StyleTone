#!/usr/bin/env python3
"""Render WP-09 pairing flow mockups from the design tokens.

These are layout mockups, not simulator captures: this workspace has no macOS
toolchain. Every colour, spacing and string below mirrors the implemented
tokens (`StyleToneTheme`) and `PairingCopy`, so the images can be compared with
the SwiftUI source one-to-one.

Usage: python tools/render_screens.py
Output: screenshots/*.png
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "screenshots"
FONT_DIR = Path(r"C:\Windows\Fonts")

S = 2  # render at 2x for a retina-looking PNG
W, H = 390, 844

# Design tokens (dark, standard contrast) from ColorTokens.swift.
BG = (0x0C, 0x0D, 0x10)
SURFACE = (0x14, 0x16, 0x1A)
SURFACE_ELEVATED = (0x1C, 0x1F, 0x25)
SURFACE_PRESSED = (0x27, 0x2B, 0x33)
PHOTO_BG = (0x2E, 0x2E, 0x2E)  # 18% neutral grey
TEXT = (0xF4, 0xF5, 0xF7)
TEXT2 = (0xB6, 0xBB, 0xC5)
TEXT3 = (0x8A, 0x91, 0x9D)
ACCENT = (0xDF, 0xA7, 0x6C)
ON_ACCENT = (0x14, 0x16, 0x1A)
BORDER = (0x2A, 0x2F, 0x37)
BORDER_STRONG = (0x3E, 0x45, 0x50)
SUCCESS = (0x5B, 0xD6, 0xA2)
WARNING = (0xF2, 0xC6, 0x6D)
ERROR = (0xFF, 0x8A, 0x8A)
DISABLED_BG = (0x22, 0x26, 0x2D)
ON_DISABLED = (0x9A, 0xA1, 0xAC)
SCRIM = (0x00, 0x00, 0x00)
SYSTEM_BLUE = (0x0A, 0x84, 0xFF)


def px(value: float) -> int:
    return int(round(value * S))


def load_font(size_pt: float, weight: str = "regular") -> ImageFont.FreeTypeFont:
    files = {
        "regular": "segoeui.ttf",
        "semibold": "seguisb.ttf",
        "bold": "segoeuib.ttf",
    }
    return ImageFont.truetype(str(FONT_DIR / files[weight]), px(size_pt))


def blend(foreground: tuple[int, int, int], background: tuple[int, int, int], alpha: float):
    return tuple(
        int(round(f * alpha + b * (1 - alpha))) for f, b in zip(foreground, background)
    )


class Phone:
    def __init__(self, nav_title: str = "Pairing", scroll_note: bool = False):
        self.image = Image.new("RGB", (px(W), px(H)), BG)
        self.draw = ImageDraw.Draw(self.image)
        self.nav_title = nav_title
        self._chrome()
        self.y = 108
        if scroll_note:
            self.y += 0

    # ---------- primitives ----------

    def text(
        self,
        x: float,
        y: float,
        value: str,
        size: float = 15,
        weight: str = "regular",
        color=TEXT,
        anchor: str = "la",
    ) -> None:
        self.draw.text(
            (px(x), px(y)),
            value,
            font=load_font(size, weight),
            fill=color,
            anchor=anchor,
        )

    def text_width(self, value: str, size: float, weight: str = "regular") -> float:
        return self.draw.textlength(value, font=load_font(size, weight)) / S

    def wrap(self, value: str, width: float, size: float, weight: str = "regular"):
        font = load_font(size, weight)
        lines: list[str] = []
        current = ""
        for word in value.split():
            trial = word if not current else f"{current} {word}"
            if self.draw.textlength(trial, font=font) <= px(width):
                current = trial
            else:
                if current:
                    lines.append(current)
                current = word
        if current:
            lines.append(current)
        return lines

    def paragraph(
        self,
        x: float,
        y: float,
        value: str,
        width: float,
        size: float = 15,
        weight: str = "regular",
        color=TEXT,
        line_height: float | None = None,
    ) -> float:
        height = line_height if line_height is not None else size * 1.38
        font = load_font(size, weight)
        for line in self.wrap(value, width, size, weight):
            self.draw.text((px(x), px(y)), line, font=font, fill=color)
            y += height
        return y

    def card(
        self,
        x: float,
        y: float,
        w: float,
        h: float,
        fill=SURFACE,
        radius: float = 16,
        border=BORDER,
        dashed: bool = False,
    ) -> None:
        box = [px(x), px(y), px(x + w), px(y + h)]
        if dashed:
            self.draw.rounded_rectangle(box, radius=px(radius), fill=fill)
            self._dashed_outline(x, y, w, h, radius, border)
        else:
            self.draw.rounded_rectangle(
                box,
                radius=px(radius),
                fill=fill,
                outline=border,
                width=max(1, px(1)),
            )

    def _dashed_outline(self, x, y, w, h, radius, color):
        # Simple dashed rounded outline: short segments along the four edges.
        dash, gap = 6, 4
        step = dash + gap
        for offset in range(0, int(w) - int(radius * 2), step):
            self.draw.line(
                [px(x + radius + offset), px(y), px(x + radius + offset + dash), px(y)],
                fill=color,
                width=px(1),
            )
            self.draw.line(
                [
                    px(x + radius + offset),
                    px(y + h),
                    px(x + radius + offset + dash),
                    px(y + h),
                ],
                fill=color,
                width=px(1),
            )
        for offset in range(0, int(h) - int(radius * 2), step):
            self.draw.line(
                [px(x), px(y + radius + offset), px(x), px(y + radius + offset + dash)],
                fill=color,
                width=px(1),
            )
            self.draw.line(
                [
                    px(x + w),
                    px(y + radius + offset),
                    px(x + w),
                    px(y + radius + offset + dash),
                ],
                fill=color,
                width=px(1),
            )

    def button(
        self,
        x: float,
        y: float,
        w: float,
        label: str,
        *,
        h: float = 48,
        role: str = "secondary",
        enabled: bool = True,
        icon: str | None = None,
        center: bool = True,
    ) -> None:
        if role == "primary":
            fill = ACCENT if enabled else DISABLED_BG
            fg = ON_ACCENT if enabled else ON_DISABLED
            outline = None
        elif role == "destructive":
            fill = ERROR if enabled else DISABLED_BG
            fg = (0x1B, 0x0D, 0x0D) if enabled else ON_DISABLED
            outline = None
        else:
            fill = SURFACE_ELEVATED if enabled else DISABLED_BG
            fg = TEXT if enabled else ON_DISABLED
            outline = BORDER if enabled else BORDER
        self.draw.rounded_rectangle(
            [px(x), px(y), px(x + w), px(y + h)],
            radius=px(12),
            fill=fill,
            outline=outline,
            width=max(1, px(1)) if outline else 0,
        )
        label_width = self.text_width(label, 17, "semibold")
        icon_width = 16 if icon else 0
        total = label_width + (icon_width + 8 if icon else 0)
        start = x + (w - total) / 2 if center else x + 16
        if icon:
            self.text(start, y + h / 2, icon, 15, "regular", fg, anchor="lm")
            start += icon_width + 8
        self.text(start, y + h / 2, label, 17, "semibold", fg, anchor="lm")

    def badge(self, x: float, y: float, label: str, color) -> float:
        width = self.text_width(label, 12) + 26
        self.draw.rounded_rectangle(
            [px(x), px(y), px(x + width), px(y + 22)],
            radius=px(11),
            fill=blend(color, SURFACE, 0.16),
        )
        self.draw.ellipse(
            [px(x + 9), px(y + 9), px(x + 13), px(y + 13)],
            fill=color,
        )
        self.text(x + 18, y + 11, label, 12, "semibold", color, anchor="lm")
        return width

    def bullets(self, x: float, y: float, items: list[str], width: float) -> float:
        for item in items:
            self.text(x, y + 1, "•", 13, "regular", TEXT3)
            y = self.paragraph(x + 10, y, item, width - 10, 13, color=TEXT2)
            y += 2
        return y

    def photo(self, x, y, w, h, variant: int = 0, radius: float = 16) -> None:
        width, height = px(w), px(h)
        image = Image.new("RGB", (width, height))
        painter = ImageDraw.Draw(image)
        top = (26, 30, 38) if variant == 0 else (20, 34, 38)
        bottom = (196, 158, 116) if variant == 0 else (104, 148, 142)
        for row in range(height):
            t = row / max(1, height - 1)
            color = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
            painter.line([(0, row), (width, row)], fill=color)
        head = width * 0.17
        painter.ellipse(
            [width * 0.5 - head, height * 0.26 - head * 1.2,
             width * 0.5 + head, height * 0.26 + head * 1.2],
            fill=(58, 48, 42) if variant == 0 else (38, 54, 52),
        )
        painter.ellipse(
            [width * 0.5 - width * 0.33, height * 0.5,
             width * 0.5 + width * 0.33, height * 1.08],
            fill=(64, 52, 44) if variant == 0 else (42, 58, 56),
        )
        mask = Image.new("L", (width, height), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [0, 0, width - 1, height - 1], radius=px(radius), fill=255
        )
        self.image.paste(image, (px(x), px(y)), mask)
        self.draw.rounded_rectangle(
            [px(x), px(y), px(x + w), px(y + h)],
            radius=px(radius),
            outline=BORDER,
            width=max(1, px(1)),
        )

    def empty_photo(self, x, y, w, h, label: str, radius: float = 16) -> None:
        self.draw.rounded_rectangle(
            [px(x), px(y), px(x + w), px(y + h)],
            radius=px(radius),
            fill=PHOTO_BG,
            outline=BORDER,
            width=max(1, px(1)),
        )
        # simple photo glyph
        cx, cy = x + w / 2, y + h / 2 - 8
        self.draw.rounded_rectangle(
            [px(cx - 16), px(cy - 12), px(cx + 16), px(cy + 12)],
            radius=px(3),
            outline=TEXT3,
            width=max(1, px(1)),
        )
        self.draw.ellipse([px(cx - 9), px(cy - 6), px(cx - 3), px(cy)], fill=TEXT3)
        self.draw.polygon(
            [
                (px(cx - 12), px(cy + 8)),
                (px(cx - 2), px(cy - 2)),
                (px(cx + 7), px(cy + 8)),
            ],
            fill=TEXT3,
        )
        lines = self.wrap(label, w - 24, 13)
        start = y + h - 16 - (len(lines) - 1) * 18
        for line in lines:
            self.text(cx, start, line, 13, "regular", TEXT2, anchor="mm")
            start += 18

    def trash(self, center_x: float, top_y: float) -> None:
        self.draw.rounded_rectangle(
            [px(center_x - 7), px(top_y), px(center_x + 7), px(top_y + 3)],
            radius=px(1),
            fill=TEXT2,
        )
        self.draw.rounded_rectangle(
            [px(center_x - 9), px(top_y + 5), px(center_x + 9), px(top_y + 17)],
            radius=px(2),
            outline=TEXT2,
            width=max(1, px(1)),
        )
        for offset in (-4, 0, 4):
            self.draw.line(
                [px(center_x + offset), px(top_y + 8), px(center_x + offset), px(top_y + 14)],
                fill=TEXT2,
                width=max(1, px(1)),
            )

    def progress_card(
        self,
        x: float,
        y: float,
        w: float,
        target: int,
        eligible: int,
        good: int,
        caution: int,
        rejected: int,
    ) -> float:
        height = 158
        self.card(x, y, w, height)
        shown = min(eligible, target)
        self.text(x + 16, y + 16, f"{shown}/{target}", 24, "semibold")
        self.text(
            x + 16 + self.text_width(f"{shown}/{target}", 24, "semibold") + 10,
            y + 25,
            "Usable pairs",
            13,
            "regular",
            TEXT2,
        )
        # progress bar
        track_y = y + 54
        self.draw.rounded_rectangle(
            [px(x + 16), px(track_y), px(x + w - 16), px(track_y + 8)],
            radius=px(4),
            fill=blend(ACCENT, SURFACE, 0.18),
        )
        if target > 0 and shown > 0:
            fill_w = (w - 32) * min(1, shown / target)
            self.draw.rounded_rectangle(
                [px(x + 16), px(track_y), px(x + 16 + fill_w), px(track_y + 8)],
                radius=px(4),
                fill=ACCENT,
            )
        # counts
        count_y = y + 78
        cursor = x + 16
        for label, count, color in (
            ("Good", good, SUCCESS),
            ("Caution", caution, WARNING),
            ("Not usable", rejected, ERROR),
        ):
            self.draw.ellipse([px(cursor), px(count_y + 4), px(cursor + 8), px(count_y + 12)], fill=color)
            cursor += 14
            self.text(cursor, count_y, str(count), 15, "semibold")
            cursor += self.text_width(str(count), 15, "semibold") + 5
            self.text(cursor, count_y + 2, label, 13, "regular", TEXT2)
            cursor += self.text_width(label, 13) + 18
        # target selector
        target_y = y + 110
        self.text(x + 16, target_y + 10, "Target", 13, "regular", TEXT2)
        cursor = x + 16 + self.text_width("Target", 13) + 14
        for value in (3, 5, 8):
            selected = value == target
            box_w = 46
            self.draw.rounded_rectangle(
                [px(cursor), px(target_y), px(cursor + box_w), px(target_y + 34)],
                radius=px(17),
                fill=ACCENT if selected else SURFACE_PRESSED,
            )
            self.text(
                cursor + box_w / 2,
                target_y + 17,
                str(value),
                15,
                "semibold",
                ON_ACCENT if selected else TEXT,
                anchor="mm",
            )
            cursor += box_w + 8
        return y + height

    # ---------- chrome ----------

    def _chrome(self) -> None:
        # dynamic island
        self.draw.rounded_rectangle(
            [px(W / 2 - 60), px(11), px(W / 2 + 60), px(37)],
            radius=px(13),
            fill=(0, 0, 0),
        )
        self.text(30, 23, "9:41", 15, "semibold", anchor="lm")
        # signal
        for index, bar_h in enumerate((4, 6, 8, 10)):
            self.draw.rounded_rectangle(
                [px(302 + index * 5), px(28 - bar_h), px(305 + index * 5), px(28)],
                radius=px(1),
                fill=TEXT,
            )
        # wifi (three arcs approximated with arcs)
        self.draw.arc([px(328), px(17), px(348), px(37)], start=210, end=330, fill=TEXT, width=px(2))
        self.draw.arc([px(333), px(22), px(343), px(32)], start=210, end=330, fill=TEXT, width=px(2))
        self.draw.ellipse([px(336), px(27), px(340), px(31)], fill=TEXT)
        # battery
        self.draw.rounded_rectangle(
            [px(352), px(19), px(373), px(31)], radius=px(3), outline=TEXT, width=px(1)
        )
        self.draw.rounded_rectangle([px(354), px(21), px(368), px(29)], radius=px(1), fill=TEXT)
        self.draw.rounded_rectangle([px(374), px(23), px(376), px(27)], radius=px(1), fill=TEXT)
        # navigation bar
        nav_y = 54
        self.draw.line([px(0), px(nav_y + 44), px(W), px(nav_y + 44)], fill=BORDER, width=1)
        self.draw.line(
            [px(22), px(nav_y + 20), px(15), px(nav_y + 27), px(22), px(nav_y + 34)],
            fill=ACCENT,
            width=px(2),
            joint="curve",
        )
        self.text(W / 2, nav_y + 22, self.nav_title, 17, "semibold", anchor="mm")

    # ---------- save ----------

    def save(self, name: str) -> None:
        OUT.mkdir(parents=True, exist_ok=True)
        self.image.save(OUT / name)


# ---------------------------------------------------------------------------
# Screens
# ---------------------------------------------------------------------------


def screen_empty() -> None:
    phone = Phone("Pairing")
    x, w = 20, 350
    y = phone.y
    phone.text(x, y, "Pairing", 30, "semibold")
    y += 44
    y = phone.paragraph(
        x,
        y,
        "Show a before and after of edits you already love. StyleTone learns on this device.",
        w,
        15,
        color=TEXT2,
    )
    y += 16
    y = phone.progress_card(x, y, w, 3, 0, 0, 0, 0) + 18

    empty_h = 286
    phone.card(x, y, w, empty_h, dashed=True)
    inner = y + 16
    slot_w = (w - 32 - 12) / 2
    canvas_h = slot_w
    phone.empty_photo(x + 16, inner, slot_w, canvas_h, "Original")
    phone.empty_photo(x + 16 + slot_w + 12, inner, slot_w, canvas_h, "Edited")
    phone.text(x + w / 2, inner + canvas_h / 2, "→", 18, "regular", TEXT3, anchor="mm")
    inner += canvas_h + 14
    phone.text(x + 16, inner, "No pairs yet", 17, "semibold")
    inner += 25
    inner = phone.paragraph(
        x + 16,
        inner,
        "Pick a photo you edited and the original it started from. Three usable pairs are enough to begin.",
        w - 32,
        14,
        color=TEXT2,
    )
    phone.text(x + 16, inner + 6, "Original first, edited second.", 13, "regular", TEXT3)
    y += empty_h + 18

    phone.button(x, y, w, "Add pair", icon="+")
    y += 58
    y = phone.paragraph(
        x,
        y,
        "In the picker, choose the original first and the edited photo second.",
        w,
        13,
        color=TEXT3,
    )
    y += 8
    phone.button(x, y, w, "Continue", role="primary", enabled=False)
    y += 56
    phone.text(x, y, "Add at least 3 usable pairs to continue.", 13, "regular", TEXT3)
    phone.save("01-empty.png")


def screen_good_and_warning() -> None:
    phone = Phone("Pairing")
    x, w = 20, 350
    y = phone.y
    phone.progress_card(x, y, w, 5, 2, 1, 1, 0)
    y += 174

    card_w = w
    slot_w = (card_w - 32 - 12) / 2
    canvas_h = slot_w * 1.25

    # --- good pair ---
    card_h = 16 + 26 + 12 + canvas_h + 8 + 18 + 8 + 44 + 12 + 46 + 16
    phone.card(x, y, card_w, card_h)
    inner = y + 16
    phone.text(x + 16, inner, "Pair 1", 17, "semibold")
    badge_label = "Good"
    badge_w = phone.text_width(badge_label, 12) + 26
    phone.badge(x + card_w - 16 - 44 - 6 - badge_w, inner, badge_label, SUCCESS)
    phone.trash(x + card_w - 16 - 22, inner + 2)
    inner += 26 + 12
    phone.photo(x + 16, inner, slot_w, canvas_h, variant=0)
    phone.photo(x + 16 + slot_w + 12, inner, slot_w, canvas_h, variant=1)
    inner += canvas_h + 8
    phone.text(x + 16, inner, "Original", 15, "regular")
    phone.text(x + 16 + slot_w + 12, inner, "Edited", 15, "regular")
    inner += 22
    half = (card_w - 32 - 12) / 2
    phone.button(x + 16, inner, half, "Replace", h=44)
    phone.button(x + 16 + half + 12, inner, half, "Replace", h=44)
    inner += 44 + 12
    phone.text(x + 16, inner, "Good pair", 15, "semibold", SUCCESS)
    phone.text(x + 16, inner + 20, "The original and the edit line up well.", 13, "regular", TEXT2)
    y += card_h + 14

    # --- warning pair, clipped by the viewport ---
    if y < H - 40:
        card_h2 = card_h
        phone.card(x, y, card_w, min(card_h2, H - y - 10))
        inner = y + 16
        phone.text(x + 16, inner, "Pair 2", 17, "semibold")
        caution_w = phone.text_width("Caution", 12) + 26
        phone.badge(x + card_w - 16 - 44 - 6 - caution_w, inner, "Caution", WARNING)
        phone.trash(x + card_w - 16 - 22, inner + 2)
        inner += 38
        phone.photo(x + 16, inner, slot_w, canvas_h, variant=1)
        phone.photo(x + 16 + slot_w + 12, inner, slot_w, canvas_h, variant=0)
    phone.save("02-grades.png")


def screen_rejected() -> None:
    phone = Phone("Pairing")
    x, w = 20, 350
    y = phone.y
    phone.progress_card(x, y, w, 8, 0, 0, 0, 1)
    y += 174

    card_w = w
    slot_w = (card_w - 32 - 12) / 2
    canvas_h = slot_w * 1.25
    card_h = 16 + 26 + 12 + canvas_h + 8 + 18 + 8 + 44 + 12 + 96 + 16
    phone.card(x, y, card_w, card_h)
    inner = y + 16
    phone.text(x + 16, inner, "Pair 3", 17, "semibold")
    rejected_w = phone.text_width("Not usable", 12) + 26
    phone.badge(x + card_w - 16 - 44 - 6 - rejected_w, inner, "Not usable", ERROR)
    phone.trash(x + card_w - 16 - 22, inner + 2)
    inner += 38
    phone.photo(x + 16, inner, slot_w, canvas_h, variant=1)
    phone.photo(x + 16 + slot_w + 12, inner, slot_w, canvas_h, variant=0)
    inner += canvas_h + 8
    phone.text(x + 16, inner, "Original", 15)
    phone.text(x + 16 + slot_w + 12, inner, "Edited", 15)
    inner += 22
    half = (card_w - 32 - 12) / 2
    phone.button(x + 16, inner, half, "Replace", h=44)
    phone.button(x + 16 + half + 12, inner, half, "Replace", h=44)
    inner += 56
    phone.text(x + 16, inner, "Not usable", 15, "semibold", ERROR)
    inner += 22
    inner = phone.bullets(
        x + 16,
        inner,
        [
            "The photos do not look like the same scene.",
            "The edited photo is shifted too far to compare.",
            "This pair will not be used for learning.",
        ],
        card_w - 32,
    )
    y += card_h + 16

    phone.button(x, y, w, "Continue", role="primary", enabled=False)
    y += 56
    phone.text(x, y, "Add at least 3 usable pairs to continue.", 13, "regular", TEXT3)
    phone.save("03-rejected.png")


def screen_restored() -> None:
    phone = Phone("Pairing")
    x, w = 20, 350
    y = phone.y
    phone.progress_card(x, y, w, 3, 0, 0, 0, 0)
    y += 174

    notice_h = 92
    phone.draw.rounded_rectangle(
        [px(x), px(y), px(x + w), px(y + notice_h)],
        radius=px(12),
        fill=blend(ACCENT, SURFACE, 0.12),
        outline=blend(ACCENT, SURFACE, 0.35),
        width=max(1, px(1)),
    )
    phone.draw.ellipse([px(x + 16), px(y + 17), px(x + 32), px(y + 33)], fill=blend(ACCENT, SURFACE, 0.25))
    phone.text(x + 24, y + 25, "i", 12, "semibold", ACCENT, anchor="mm")
    phone.text(x + 44, y + 14, "Your last pairing session was restored.", 15, "semibold")
    phone.paragraph(
        x + 44,
        y + 38,
        "Photos are released when the app closes. Choose them again to reuse their pairs.",
        w - 60,
        13,
        color=TEXT2,
    )
    y += notice_h + 16

    card_w = w
    slot_w = (card_w - 32 - 12) / 2
    canvas_h = slot_w * 1.25
    card_h = 16 + 26 + 12 + canvas_h + 8 + 18 + 12 + 40 + 44 + 14 + 44 + 16
    phone.card(x, y, card_w, card_h)
    inner = y + 16
    phone.text(x + 16, inner, "Pair 1", 17, "semibold")
    restored_badge_w = phone.text_width("Incomplete", 12) + 26
    phone.badge(x + card_w - 16 - 44 - 6 - restored_badge_w, inner, "Incomplete", TEXT2)
    phone.trash(x + card_w - 16 - 22, inner + 2)
    inner += 38
    # stale slot placeholders
    phone.draw.rounded_rectangle(
        [px(x + 16), px(inner), px(x + 16 + slot_w), px(inner + canvas_h)],
        radius=px(16),
        fill=blend(WARNING, PHOTO_BG, 0.10),
        outline=blend(WARNING, BORDER, 0.35),
        width=max(1, px(1)),
    )
    phone.draw.rounded_rectangle(
        [px(x + 16 + slot_w + 12), px(inner), px(x + 16 + slot_w * 2 + 12), px(inner + canvas_h)],
        radius=px(16),
        fill=blend(WARNING, PHOTO_BG, 0.10),
        outline=blend(WARNING, BORDER, 0.35),
        width=max(1, px(1)),
    )
    stale = "Choose again"
    phone.text(x + 16 + slot_w / 2, inner + canvas_h / 2 - 8, stale, 14, "semibold", WARNING, anchor="mm")
    phone.text(
        x + 16 + slot_w + 12 + slot_w / 2,
        inner + canvas_h / 2 - 8,
        stale,
        14,
        "semibold",
        WARNING,
        anchor="mm",
    )
    inner += canvas_h + 8
    phone.text(x + 16, inner, "Original", 15)
    phone.text(x + 16 + slot_w + 12, inner, "Edited", 15)
    inner += 22
    inner = phone.paragraph(
        x + 16,
        inner,
        "The photo was released when the app closed. Pick it again to keep this pair.",
        card_w - 32,
        12,
        color=WARNING,
    )
    inner += 4
    half = (card_w - 32 - 12) / 2
    phone.button(x + 16, inner, half, "Choose", h=44)
    phone.button(x + 16 + half + 12, inner, half, "Choose", h=44)
    inner += 56
    phone.text(x + 16, inner, "Choose both photos", 15, "semibold", TEXT2)
    inner += 22
    phone.text(x + 16, inner, "\u2022", 13, "regular", TEXT3)
    phone.paragraph(
        x + 26,
        inner,
        "In the picker, choose the original first and the edited photo second.",
        card_w - 42,
        13,
        color=TEXT2,
    )
    y += card_h + 16

    phone.save("04-restored.png")


def screen_picker() -> None:
    image = Image.new("RGB", (px(W), px(H)), (28, 28, 30))
    draw = ImageDraw.Draw(image)

    def text(x, y, value, size=15, weight="regular", color=TEXT, anchor="la"):
        draw.text((px(x), px(y)), value, font=load_font(size, weight), fill=color, anchor=anchor)

    # dynamic island + status bar
    draw.rounded_rectangle(
        [px(W / 2 - 60), px(11), px(W / 2 + 60), px(37)], radius=px(13), fill=(0, 0, 0)
    )
    text(30, 23, "9:41", 15, "semibold", anchor="lm")
    # nav
    text(22, 66, "Cancel", 17, "regular", SYSTEM_BLUE)
    text(W / 2, 66, "Photos", 17, "semibold", anchor="mm")
    text(W - 22, 66, "Add", 17, "semibold", SYSTEM_BLUE, anchor="ra")
    draw.line([px(0), px(96), px(W), px(96)], fill=(58, 58, 60), width=1)

    # thumbnails grid 3 columns
    margin, gap = 2, 2
    cols = 3
    cell = (W - margin * 2 - gap * (cols - 1)) / cols
    variants = [
        (26, 30, 38, 196, 158, 116),
        (20, 34, 38, 104, 148, 142),
        (34, 28, 26, 190, 140, 120),
        (22, 32, 30, 150, 160, 130),
        (30, 26, 34, 120, 130, 170),
        (24, 30, 26, 170, 150, 110),
        (18, 30, 30, 140, 170, 150),
        (32, 24, 26, 120, 110, 130),
        (24, 28, 34, 160, 170, 180),
        (30, 30, 24, 110, 140, 120),
        (20, 26, 32, 130, 120, 150),
        (28, 34, 26, 180, 160, 130),
    ]
    for index, variant in enumerate(variants):
        row, col = divmod(index, cols)
        cx0 = margin + col * (cell + gap)
        cy0 = 108 + row * (cell + gap)
        top = variant[:3]
        bottom = variant[3:]
        block = Image.new("RGB", (px(cell), px(cell)))
        painter = ImageDraw.Draw(block)
        for py in range(px(cell)):
            t = py / max(1, px(cell) - 1)
            color = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
            painter.line([(0, py), (px(cell), py)], fill=color)
        head = px(cell) * 0.18
        painter.ellipse(
            [px(cell) * 0.5 - head, px(cell) * 0.28 - head * 1.2,
             px(cell) * 0.5 + head, px(cell) * 0.28 + head * 1.2],
            fill=blend((0, 0, 0), top, 0.35),
        )
        painter.ellipse(
            [px(cell) * 0.5 - px(cell) * 0.34, px(cell) * 0.52,
             px(cell) * 0.5 + px(cell) * 0.34, px(cell) * 1.08],
            fill=blend((0, 0, 0), top, 0.30),
        )
        image.paste(block, (px(cx0), px(cy0)))
        if index in (0, 3):
            badge_index = 1 if index == 0 else 2
            draw.ellipse(
                [px(cx0 + cell - 24), px(cy0 + 6), px(cx0 + cell - 6), px(cy0 + 24)],
                fill=SYSTEM_BLUE,
                outline=(255, 255, 255),
                width=px(1),
            )
            text(cx0 + cell - 15, cy0 + 15, str(badge_index), 12, "semibold", (255, 255, 255), anchor="mm")
    # selected footer
    draw.rounded_rectangle(
        [px(20), px(H - 62), px(W - 20), px(H - 14)],
        radius=px(24),
        fill=(44, 44, 46),
    )
    text(W / 2, H - 38, "2 selected · original, then edited", 14, "semibold", TEXT2, anchor="mm")
    # annotation
    text(W / 2, H - 78, "System PHPicker · out of process · no library permission", 12, "regular", (150, 150, 155), anchor="mm")
    image.save(OUT / "05-picker.png")


def diagram_flow() -> None:
    width, height = 1400, 780
    image = Image.new("RGB", (px(width), px(height)), BG)
    draw = ImageDraw.Draw(image)

    def text(x, y, value, size=20, weight="regular", color=TEXT, anchor="la"):
        draw.text((px(x), px(y)), value, font=load_font(size, weight), fill=color, anchor=anchor)

    def box(x, y, w, h, title, subtitle, accent=ACCENT):
        draw.rounded_rectangle(
            [px(x), px(y), px(x + w), px(y + h)],
            radius=px(14),
            fill=SURFACE,
            outline=accent,
            width=px(1.5),
        )
        text(x + 18, y + 16, title, 18, "semibold")
        for index, line in enumerate(subtitle.split("\n")):
            text(x + 18, y + 46 + index * 24, line, 13, "regular", TEXT2)

    def arrow(x1, y1, x2, y2, label=""):
        draw.line([px(x1), px(y1), px(x2), px(y2)], fill=BORDER_STRONG, width=px(2))
        import math

        angle = math.atan2(y2 - y1, x2 - x1)
        size = 7
        for offset in (-0.5, 0.5):
            draw.line(
                [
                    px(x2),
                    px(y2),
                    px(x2 - size * math.cos(angle - offset)),
                    px(y2 - size * math.sin(angle - offset)),
                ],
                fill=BORDER_STRONG,
                width=px(2),
            )
        if label:
            text((x1 + x2) / 2, (y1 + y2) / 2 - 26, label, 12, "regular", TEXT3, anchor="mm")

    text(60, 44, "Pairing flow (WP-09)", 30, "semibold")
    text(
        60,
        84,
        "System PHPicker · on-device quality check · metadata-only session",
        15,
        "regular",
        TEXT2,
    )

    box(60, 160, 240, 120, "1 · Empty", "No pairs yet\nAdd pair → picker")
    box(380, 160, 280, 120, "2 · PHPicker", "Ordered selection\noriginal → edited")
    box(740, 160, 260, 120, "3 · Import + grade", "Downsample to 1600 px\nPairQualityAnalyzing")
    box(1080, 160, 260, 120, "4 · Grade badge", "Good / Caution / Not usable\nred stays out", SUCCESS)

    box(1080, 340, 260, 120, "Continue / skip", "≥3 usable pairs → calibration\nskip → natural default", SUCCESS)
    box(740, 340, 260, 120, "Replace / delete", "Atomic import\none-level undo", WARNING)
    box(380, 340, 280, 120, "Session metadata", "JSON in app sandbox\nno pixels, no shared container", WARNING)
    box(60, 340, 240, 120, "Relaunch", "Pairs restored as\nstale slots to re-pick", WARNING)

    box(740, 510, 260, 120, "12 pairs ≤ 6 min", "Timeline instrumented\nsummary.metTimeBudget", SUCCESS)
    box(1080, 510, 260, 120, "Privacy guard", "PHPicker only\nsource audit test", ACCENT)

    arrow(300, 220, 380, 220)
    arrow(660, 220, 740, 220)
    arrow(1000, 220, 1080, 220)
    arrow(1210, 280, 1210, 340)

    text(
        60,
        680,
        "Green = good pair, yellow = usable with caution, red = excluded from learning. "
        "Supporting boxes describe invariants, not a second flow.",
        13,
        "regular",
        TEXT3,
    )
    image.save(OUT / "06-flow.png")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    screen_empty()
    screen_good_and_warning()
    screen_rejected()
    screen_restored()
    screen_picker()
    diagram_flow()
    print(f"rendered {len(list(OUT.glob('*.png')))} images in {OUT}")


if __name__ == "__main__":
    main()
