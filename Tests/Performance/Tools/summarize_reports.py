#!/usr/bin/env python3
"""Print a Markdown summary of WP-24 performance JSON reports."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

UNIT_SYMBOL = {
    "seconds": "s",
    "framesPerSecond": "fps",
    "megabytes": "MB",
    "count": "count",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reports", required=True, type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    rows = []
    blocking = 0
    for path in sorted(args.reports.rglob("*.json")):
        try:
            report = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if "verdicts" not in report:
            continue
        environment = report.get("environment", {}).get("id", "?")
        commit = report.get("commit", "?")
        for verdict in report["verdicts"]:
            status = verdict.get("status", "?")
            is_blocking = status in {
                "regression", "contractExceeded", "insufficientSamples",
                "invalidBaseline", "invalidMeasurement", "baselineRequired",
            }
            blocking += 1 if is_blocking else 0
            rows.append((
                environment,
                commit,
                verdict.get("scenarioID", "?"),
                verdict.get("measuredValue"),
                verdict.get("baselineValue"),
                verdict.get("unit", "?"),
                status,
            ))

    print("| Environment | Commit | Scenario | p95 | Baseline | Status |")
    print("|---|---|---|---:|---:|---|")
    for environment, commit, scenario, measured, baseline, unit, status in rows:
        symbol = UNIT_SYMBOL.get(unit, unit)
        measured_text = "—" if measured is None else f"{measured:.4f} {symbol}"
        baseline_text = "—" if baseline is None else f"{baseline:.4f} {symbol}"
        print(f"| `{environment}` | `{commit}` | `{scenario}` | {measured_text} "
              f"| {baseline_text} | {status} |")
    print()
    print(f"Blocking verdicts: {blocking}")
    return 1 if blocking else 0


if __name__ == "__main__":
    raise SystemExit(main())
