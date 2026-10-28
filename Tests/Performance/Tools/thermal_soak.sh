#!/usr/bin/env bash
#
# Record a thermal soak trace on a connected device.
#
# The App must be running the editor; this script records the system/GPU trace
# and collects the device log. Thermal-state transitions and the in-app
# performance tier must be read from the `editor.performance.*` notice/signpost
# or the diagnostics screen; iOS does not expose thermalState to a host CLI.
#
# Usage:
#   Tests/Performance/Tools/thermal_soak.sh <DEVICE_UDID> [SECONDS]
set -euo pipefail

UDID="${1:-}"
DURATION="${2:-600}"
if [[ -z "$UDID" ]]; then
  echo "usage: $0 <DEVICE_UDID> [SECONDS]" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${ST_PERF_TRACE_DIR:-$ROOT/.perf-traces}"
mkdir -p "$OUT"

TRACE="$OUT/thermal-$STAMP.trace"
LOGARCHIVE="$OUT/thermal-$STAMP.logarchive"

echo "Recording $DURATION s of Metal/Points-of-Interest on $UDID"
echo "Start dragging a face/body slider continuously now."

xcrun xctrace record \
  --template 'Metal System Trace' \
  --device "$UDID" \
  --time-limit "${DURATION}s" \
  --output "$TRACE" &
TRACE_PID=$!

# Take a device log snapshot while the soak is running.
sleep "$DURATION"
xcrun devicectl device info processes --device "$UDID" >/dev/null 2>&1 || true
log collect --device "$UDID" --last "${DURATION}s" --output "$LOGARCHIVE" 2>/dev/null || \
  echo "note: log collect failed; use Xcode Devices > Open Console"

wait "$TRACE_PID" || true
echo "trace: $TRACE"
echo "log:   $LOGARCHIVE"
echo
echo "Acceptance: no Jetsam; critical thermal not sustained >60 s;"
echo "last 3 min p95 frame time <= 1/24 s (severe throttle guard);"
echo "target is >=30 fps on iPhone 13."
