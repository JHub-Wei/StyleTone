#!/usr/bin/env python3
"""Merge WP-24 performance JSON reports into the committed baseline file.

The script is deliberately conservative:

* it only writes entries for one explicit ``--environment``;
* one-sample informational reports are ignored;
* existing entries for other environments are preserved;
* the JSON is written with sorted keys so the diff is reviewable.

Usage:
    python3 Tests/Performance/Tools/record_baseline.py \
        --environment device.iphone13 \
        --reports .perf-reports \
        --commit "$(git rev-parse --short HEAD)"

The report format is produced by ``PerformanceReport``; either the
``ST_PERF_REPORT_DIR`` files or attachments exported from an ``.xcresult`` work.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import sys
from pathlib import Path
from typing import Any

DEFAULT_BASELINE = Path("Tests/Performance/Baselines/performance-baselines.json")

# Measurements with too few samples are diagnostics, not baselines. The real
# per-scenario minimum is enforced by PerformanceGate; this is a coarse guard.
MIN_SAMPLES = 2


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reports", required=True, type=Path,
                        help="directory with performance-*.json reports")
    parser.add_argument("--environment", required=True,
                        help="environment id to update, e.g. device.iphone13")
    parser.add_argument("--baseline", type=Path, default=DEFAULT_BASELINE)
    parser.add_argument("--commit", default="unknown")
    parser.add_argument("--source", default=None,
                        help="override the report source label")
    parser.add_argument("--no-gate", action="store_true",
                        help="write entries with gateEnabled=false")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def load_baseline(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {
            "schemaVersion": 1,
            "generatedAt": _now(),
            "referenceDevice": "iPhone 13",
            "notes": "Created by record_baseline.py",
            "entries": [],
        }
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def iter_reports(directory: Path):
    for path in sorted(directory.rglob("*.json")):
        try:
            with path.open("r", encoding="utf-8") as handle:
                data = json.load(handle)
        except (OSError, json.JSONDecodeError) as error:
            print(f"skip {path}: {error}", file=sys.stderr)
            continue
        if isinstance(data, dict) and "observations" in data and "verdicts" in data:
            yield path, data


def collect_entries(
    directory: Path,
    environment: str,
    commit: str,
    source_override: str | None,
    gate_enabled: bool,
):
    entries: list[dict[str, Any]] = []
    for path, report in iter_reports(directory):
        observations = report.get("observations") or []
        verdicts = report.get("verdicts") or []
        for index, observation in enumerate(observations):
            measurement = observation.get("measurement") or {}
            env = observation.get("environment") or {}
            if env.get("id") != environment:
                continue
            sample_count = int(measurement.get("sampleCount") or 0)
            if sample_count < MIN_SAMPLES:
                print(f"skip {path.name} #{index}: only {sample_count} sample(s)")
                continue
            status = verdicts[index].get("status") if index < len(verdicts) else None
            if status in {"informational", "invalidMeasurement", "insufficientSamples"}:
                print(f"skip {path.name} #{index}: verdict {status}")
                continue
            scenario = measurement.get("scenarioID")
            if not scenario:
                continue
            statistic = "p95"
            if index < len(verdicts):
                statistic = verdicts[index].get("statistic", "p95")
            if statistic not in {"p50", "p95"}:
                statistic = "p95"
            value = float(measurement[statistic])
            entries.append({
                "scenarioID": scenario,
                "environmentID": environment,
                "value": value,
                "unit": measurement["unit"],
                "statistic": statistic,
                "sampleCount": sample_count,
                "recordedAt": report.get("generatedAt") or _now(),
                "commit": commit if commit != "unknown" else report.get("commit", "unknown"),
                "source": source_override or f"{path.name}#{index}",
                "notes": observation.get("notes"),
                "gateEnabled": gate_enabled,
            })
    return entries


def _now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def main() -> int:
    global args
    args = parse_args()
    baseline = load_baseline(args.baseline)
    if baseline.get("schemaVersion") != 1:
        print(f"error: unsupported baseline schema {baseline.get('schemaVersion')}", file=sys.stderr)
        return 2

    new_entries = collect_entries(
        args.reports,
        args.environment,
        args.commit,
        args.source,
        gate_enabled=not args.no_gate,
    )
    if not new_entries:
        print("error: no gated observations found", file=sys.stderr)
        return 1

    by_key = {
        (entry["scenarioID"], entry["environmentID"]): entry
        for entry in baseline.get("entries", [])
    }
    for entry in new_entries:
        key = (entry["scenarioID"], entry["environmentID"])
        previous = by_key.get(key)
        if previous:
            delta = (entry["value"] - previous["value"]) / previous["value"] * 100
            print(f"{entry['scenarioID']}: {previous['value']:.4f} -> "
                  f"{entry['value']:.4f} ({delta:+.1f}%)")
        else:
            print(f"{entry['scenarioID']}: new {entry['value']:.4f}")
        by_key[key] = entry

    baseline["entries"] = sorted(
        by_key.values(),
        key=lambda item: (item["environmentID"], item["scenarioID"]),
    )
    baseline["generatedAt"] = _now()

    text = json.dumps(baseline, indent=2, ensure_ascii=False, sort_keys=True) + "\n"
    if args.dry_run:
        print(text)
        return 0

    args.baseline.parent.mkdir(parents=True, exist_ok=True)
    args.baseline.write_text(text, encoding="utf-8")
    print(f"wrote {args.baseline} ({len(baseline['entries'])} entries)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
