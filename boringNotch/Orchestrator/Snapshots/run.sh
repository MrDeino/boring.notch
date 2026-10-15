#!/bin/sh
# Snapshot harness: renders the Orchestrator tab at the real notch sizes with fixture data.
# Needs one app build first (for the Defaults module): xcodebuild ... -derivedDataPath "${DD:-/tmp/notch-dd}" build
# Usage: boringNotch/Orchestrator/Snapshots/run.sh [--image-renderer]   ->  /tmp/notch-snapshots/*.png
#        boringNotch/Orchestrator/Snapshots/run.sh --transition   ->  top-edge check over grow/collapse/stock-open steps
#        boringNotch/Orchestrator/Snapshots/run.sh --closed       ->  closed-notch wings + music indicator (closed-*.png)
#        boringNotch/Orchestrator/Snapshots/run.sh --hittest      ->  clicks composer/segment/capsule in the real tab (no POSTs)
#        boringNotch/Orchestrator/Snapshots/run.sh --idle         ->  idle CPU per scene + outside-click/close-gate checks (IDLE_REPORT=1: never fail, IDLE_SAMPLE=1: sample hot scenes)
#        OPT=-O boringNotch/Orchestrator/Snapshots/run.sh --idle  ->  optimized harness (what a Release build costs)
#        OPT=-O boringNotch/Orchestrator/Snapshots/run.sh --frames  ->  frame intervals per transition (open/expand/collapse/close), FAIL over 20 ms (FRAMES_REPORT=1: never fail)
#        Redirect output to a file (> log) rather than piping: --hittest can leave a pipe open after it exits.
set -e
cd "$(dirname "$0")/../../.."
P="${DD:-/tmp/notch-dd}/Build/Products/Debug"
B="${SNAP_BUILD:-/tmp/notch-snap-build}" # SNAP_BUILD=<dir>: own binary when another checkout runs the harness at the same time
mkdir -p "$B"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse-as-library -swift-version 5 \
  -target arm64-apple-macos14.0 $OPT -D ORCH_SNAPSHOT -I "$P" -o "$B/snap" \
  $(ls boringNotch/Orchestrator/Orchestrator*.swift) boringNotch/Orchestrator/Snapshots/*.swift boringNotch/components/Notch/NotchShape.swift "$P/Defaults.o"
"$B/snap" "$@"
