#!/usr/bin/env python3
"""Generate the deterministic 100-sample WP-25 synthetic portrait corpus.

The corpus is metadata only. Pixels are drawn by
``Tests/GoldenSupport/Sources/GoldenSupport/PortraitRenderer.swift`` from these
descriptions; no photograph is read or stored.

Usage:
    python Tests/Integration/Tools/generate_portrait_corpus.py
    python Tests/Integration/Tools/generate_portrait_corpus.py --check

``--check`` regenerates in memory, validates the quotas and compares the
committed JSON byte-for-byte (sorted keys, two-space indent).
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
CORPUS_PATH = REPO_ROOT / "Tests" / "Integration" / "Corpus" / "portrait-corpus.json"
SCHEMA_VERSION = 1
CORPUS_VERSION = "2026.10.27"
GENERATOR = "Tests/Integration/Tools/generate_portrait_corpus.py"

TONE_NAMES = {1: "I", 2: "II", 3: "III", 4: "IV", 5: "V", 6: "VI"}
BODY_TYPES = ["slim", "average", "curvy", "plus", "tall", "petite"]
BACKGROUNDS = (
    ["doorFrame"] * 20
    + ["floorTiles"] * 20
    + ["doorFrameAndTiles"] * 20
    + ["window"] * 15
    + ["tableEdge"] * 15
    + ["plain"] * 10
)
FRAMINGS = ["headshot"] * 25 + ["halfBody"] * 40 + ["fullBody"] * 35
LIGHTING = (
    ["softKey"] * 25
    + ["sideKey"] * 20
    + ["backlit"] * 15
    + ["lowKey"] * 15
    + ["highKey"] * 15
    + ["mixed"] * 10
)
PERSON_COUNTS = [1] * 70 + [2] * 20 + [3] * 10

OCCLUSIONS_BY_FRAMING = {
    "headshot": ["none"] * 15
    + ["hairOverFace"] * 5
    + ["handAtChin"] * 3
    + ["scarf"] * 2,
    "halfBody": ["none"] * 22
    + ["armAcrossTorso"] * 6
    + ["handAtChin"] * 5
    + ["objectInFront"] * 5
    + ["scarf"] * 2,
    "fullBody": ["none"] * 18
    + ["armAcrossTorso"] * 4
    + ["objectInFront"] * 3
    + ["looseSleeves"] * 4
    + ["scarf"] * 1
    + ["hairOverFace"] * 5,
}

assert sum(len(values) for values in OCCLUSIONS_BY_FRAMING.values()) == 100
assert sum(OCCLUSIONS_BY_FRAMING["headshot"].count(name) for name in set(OCCLUSIONS_BY_FRAMING["headshot"])) == 25
assert len(FRAMINGS) == 100 and len(BACKGROUNDS) == 100 and len(LIGHTING) == 100
assert len(PERSON_COUNTS) == 100


def build_corpus() -> dict:
    rng = random.Random(2501)

    tones = [index % 6 + 1 for index in range(100)]
    bodies = [BODY_TYPES[index % len(BODY_TYPES)] for index in range(100)]

    samples = []
    background_assignment = BACKGROUNDS.copy()
    framing_assignment = FRAMINGS.copy()
    lighting_assignment = LIGHTING.copy()
    person_assignment = PERSON_COUNTS.copy()
    rng.shuffle(background_assignment)
    rng.shuffle(framing_assignment)
    rng.shuffle(lighting_assignment)
    rng.shuffle(person_assignment)

    occlusion_pools = {
        framing: OCCLUSIONS_BY_FRAMING[framing].copy() for framing in OCCLUSIONS_BY_FRAMING
    }
    for pool in occlusion_pools.values():
        rng.shuffle(pool)

    for index in range(100):
        framing = framing_assignment[index]
        occlusion = occlusion_pools[framing].pop()
        tone = tones[index]
        body = bodies[index]
        person_count = person_assignment[index]

        primary = {
            "role": "primary",
            "skinTone": tone,
            "bodyType": body,
            "occlusion": occlusion,
            "xOffset": 0.0,
            "scale": 1.0,
            "seed": 1000 + index * 13,
        }
        subjects = [primary]

        if person_count >= 2:
            # Put the primary and partner side by side, alternating sides.
            side = -1 if index % 2 == 0 else 1
            primary["xOffset"] = -0.10 * side
            partner_tone = (tone % 6) + 1
            subjects.append(
                {
                    "role": "partner",
                    "skinTone": partner_tone,
                    "bodyType": BODY_TYPES[(index + 3) % len(BODY_TYPES)],
                    "occlusion": "none",
                    "xOffset": 0.24 * side,
                    "scale": 0.86,
                    "seed": 2000 + index * 17,
                }
            )
        if person_count >= 3:
            extra_tone = ((tone + 2) % 6) + 1
            subjects.append(
                {
                    "role": "extra",
                    "skinTone": extra_tone,
                    "bodyType": BODY_TYPES[(index + 5) % len(BODY_TYPES)],
                    "occlusion": "none",
                    "xOffset": -0.30 if index % 2 == 0 else 0.30,
                    "scale": 0.74,
                    "seed": 3000 + index * 19,
                }
            )

        note = (
            f"tone {TONE_NAMES[tone]} / {body} / {framing} / "
            f"{background_assignment[index]} / {occlusion} / {person_count}p"
        )
        samples.append(
            {
                "id": f"ps-{index + 1:03d}",
                "seed": 5000 + index * 31,
                "width": 360,
                "height": 480,
                "framing": framing,
                "background": background_assignment[index],
                "lighting": lighting_assignment[index],
                "subjects": subjects,
                "note": note,
            }
        )

    return {
        "schemaVersion": SCHEMA_VERSION,
        "corpusVersion": CORPUS_VERSION,
        "generator": GENERATOR,
        "description": (
            "100 deterministic synthetic portraits for WP-25. Metadata only: "
            "pixels are rendered by GoldenSupport; no photographs are stored."
        ),
        "samples": samples,
    }


def coverage(corpus: dict) -> dict:
    tones: Counter[str] = Counter()
    bodies: Counter[str] = Counter()
    backgrounds: Counter[str] = Counter()
    framings: Counter[str] = Counter()
    person_counts: Counter[str] = Counter()
    occlusions: Counter[str] = Counter()
    multi = 0
    occluded = 0
    door = 0
    tiles = 0
    for sample in corpus["samples"]:
        primary = sample["subjects"][0]
        tones[TONE_NAMES[primary["skinTone"]]] += 1
        bodies[primary["bodyType"]] += 1
        backgrounds[sample["background"]] += 1
        framings[sample["framing"]] += 1
        person_counts[str(len(sample["subjects"]))] += 1
        if len(sample["subjects"]) > 1:
            multi += 1
        if any(subject["occlusion"] != "none" for subject in sample["subjects"]):
            occluded += 1
        for subject in sample["subjects"]:
            if subject["occlusion"] != "none":
                occlusions[subject["occlusion"]] += 1
        if sample["background"] in ("doorFrame", "doorFrameAndTiles"):
            door += 1
        if sample["background"] in ("floorTiles", "doorFrameAndTiles"):
            tiles += 1
    return {
        "total": len(corpus["samples"]),
        "tones": dict(sorted(tones.items())),
        "bodies": dict(sorted(bodies.items())),
        "backgrounds": dict(sorted(backgrounds.items())),
        "framings": dict(sorted(framings.items())),
        "personCounts": dict(sorted(person_counts.items())),
        "occlusions": dict(sorted(occlusions.items())),
        "multiPerson": multi,
        "occlusionSamples": occluded,
        "doorFrameSamples": door,
        "floorTileSamples": tiles,
    }


def validate(corpus: dict) -> None:
    samples = corpus["samples"]
    assert len(samples) == 100, len(samples)
    assert len({sample["id"] for sample in samples}) == 100
    stats = coverage(corpus)
    assert len(stats["tones"]) == 6, stats["tones"]
    assert min(stats["tones"].values()) >= 10, stats["tones"]
    assert set(stats["bodies"]) == set(BODY_TYPES), stats["bodies"]
    assert min(stats["bodies"].values()) >= 10, stats["bodies"]
    assert stats["doorFrameSamples"] >= 30, stats
    assert stats["floorTileSamples"] >= 30, stats
    assert stats["multiPerson"] >= 25, stats
    assert stats["occlusionSamples"] >= 30, stats
    assert min(stats["framings"].values()) >= 15, stats["framings"]
    for sample in samples:
        assert 1 <= len(sample["subjects"]) <= 3
        assert sample["subjects"][0]["role"] == "primary"
        assert 96 <= sample["width"] <= 4096 and 128 <= sample["height"] <= 4096
        assert abs(sample["subjects"][0]["xOffset"]) <= 0.4
        if sample["framing"] == "headshot":
            assert all(
                subject["occlusion"] != "armAcrossTorso" for subject in sample["subjects"]
            )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    corpus = build_corpus()
    validate(corpus)
    text = json.dumps(corpus, indent=2, sort_keys=True, ensure_ascii=False) + "\n"

    stats = coverage(corpus)
    print(json.dumps(stats, indent=2, sort_keys=True))

    if args.check:
        committed = CORPUS_PATH.read_text(encoding="utf-8")
        if committed != text:
            print(f"corpus differs from {CORPUS_PATH}", file=sys.stderr)
            return 1
        print(f"corpus is up to date: {CORPUS_PATH}")
        return 0

    CORPUS_PATH.parent.mkdir(parents=True, exist_ok=True)
    CORPUS_PATH.write_text(text, encoding="utf-8")
    print(f"wrote {CORPUS_PATH} ({len(corpus['samples'])} samples)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
