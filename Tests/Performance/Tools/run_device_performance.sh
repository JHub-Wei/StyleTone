#!/usr/bin/env bash
#
# Run the WP-24 performance suite on a connected iOS device.
#
# The suite is a SwiftPM test target. Xcode 15+ exposes package test targets as
# schemes; if your Xcode does not, open Package.swift, select
# `StyleTonePerformanceTests`, choose the device, and run once to generate the
# scheme, then re-run this script.
#
# Usage:
#   Tests/Performance/Tools/run_device_performance.sh <DEVICE_UDID> [SCHEME]
#
# Environment:
#   ST_PERF_REPORT_DIR   host directory for JSON/Markdown artifacts
#   ST_PERF_HEAVY=1      run the 8-pair learning scenario
#   ST_PERF_REQUIRE_BASELINE=1  fail when a baseline is missing
set -euo pipefail

UDID="${1:-}"
SCHEME="${2:-StyleTonePerformanceTests}"
if [[ -z "$UDID" ]]; then
  echo "usage: $0 <DEVICE_UDID> [SCHEME]" >&2
  echo "list devices: xcrun xctrace list devices" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_DIR="${ST_PERF_REPORT_DIR:-$ROOT/.perf-reports}"
RESULT_BUNDLE="${ST_PERF_RESULT_BUNDLE:-$REPORT_DIR/StyleTonePerformance-$STAMP.xcresult}"
mkdir -p "$REPORT_DIR"

export ST_PERF_REPORT_DIR="$REPORT_DIR"
export ST_PERF_REQUIRE_BASELINE="${ST_PERF_REQUIRE_BASELINE:-1}"
export ST_PERF_HEAVY="${ST_PERF_HEAVY:-1}"
export ST_PERF_COMMIT="${ST_PERF_COMMIT:-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)}"

echo "device:    $UDID"
echo "scheme:    $SCHEME"
echo "reports:   $REPORT_DIR"
echo "xcresult:  $RESULT_BUNDLE"

set +e
xcodebuild test \
  -scheme "$SCHEME" \
  -destination "platform=iOS,id=$UDID" \
  -derivedDataPath "$ROOT/.build/perf-derived" \
  -resultBundlePath "$RESULT_BUNDLE" \
  CODE_SIGNING_ALLOWED=YES
STATUS=$?
set -e

if [[ -d "$RESULT_BUNDLE" ]]; then
  # Xcode 16 syntax; older Xcode uses `xcresulttool export attachments --legacy`.
  xcrun xcresulttool export attachments \
    --path "$RESULT_BUNDLE" \
    --output-path "$REPORT_DIR/attachments-$STAMP" 2>/dev/null || \
    echo "note: export attachments failed; open the xcresult in Xcode"
fi

echo
echo "device run finished with status $STATUS"
echo "baseline update:"
echo "  python3 Tests/Performance/Tools/record_baseline.py \\"
echo "    --environment device.iphone13 \\"
echo "    --reports \"$REPORT_DIR\" \\"
echo "    --commit \"$ST_PERF_COMMIT\""
exit "$STATUS"
