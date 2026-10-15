#!/bin/sh
# Snapshot harness: renders the Orchestrator tab at the real notch sizes with fixture data.
# Needs one app build first (for the Defaults module): xcodebuild ... -derivedDataPath "${DD:-/tmp/notch-dd}" build
# Usage: boringNotch/Orchestrator/Snapshots/run.sh [--image-renderer]   ->  /tmp/notch-snapshots/*.png
#        boringNotch/Orchestrator/Snapshots/run.sh --transition   ->  top-edge check over grow/collapse/stock-open steps
#        boringNotch/Orchestrator/Snapshots/run.sh --closed       ->  closed-notch wings + music indicator (closed-*.png)
#        boringNotch/Orchestrator/Snapshots/run.sh --hittest      ->  clicks composer/segment/capsule in the real tab (no POSTs)
#        boringNotch/Orchestrator/Snapshots/run.sh --idle         ->  idle CPU per scene + outside-click/close-gate checks (IDLE_REPORT=1: never fail, IDLE_SAMPLE=1: sample hot scenes)
#        OPT=-O boringNotch/Orchestrator/Snapshots/run.sh --idle  ->  optimized harness (what a Release build costs)
#        Redirect output to a file (> log) rather than piping: --hittest can leave a pipe open after it exits.
set -e
cd "$(dirname "$0")/../../.."
P="${DD:-/tmp/notch-dd}/Build/Products/Debug"
mkdir -p /tmp/notch-snap-build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse-as-library -swift-version 5 \
  -target arm64-apple-macos14.0 $OPT -D ORCH_SNAPSHOT -I "$P" -o /tmp/notch-snap-build/snap \
  $(ls boringNotch/Orchestrator/Orchestrator*.swift) boringNotch/Orchestrator/Snapshots/*.swift "$P/Defaults.o"
/tmp/notch-snap-build/snap "$@"
