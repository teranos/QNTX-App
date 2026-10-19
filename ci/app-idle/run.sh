#!/usr/bin/env bash
# The app as the phone runs it — QNTX-App's shell, Apple's web view, not Safari —
# booted in the iPhone Simulator and left alone.
#
#   "WebKit's own guidance suggests aiming for less than 3% average CPU usage
#   during an idle session, with a recording of at least 15 seconds"
#
# Run from the QNTX-App checkout, with QNTX beside it at qntx/ and the page the
# app is to carry already in qntx/internal/server/dist.
#   bash ci/app-idle/run.sh <name>
set -euxo pipefail

NAME="$1"

# The page is compiled into the app, so a build from a clean output.
rm -rf gen/apple/build
cargo tauri ios build --target aarch64-sim --no-sign --debug
APP=$(find gen/apple/build -maxdepth 4 -name '*.app' -path '*arm64-sim*' | head -1)
test -n "$APP"
echo "app: $APP"

xcrun simctl terminate "$UDID" nl.sbvh.qntx || true
xcrun simctl uninstall "$UDID" nl.sbvh.qntx || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" nl.sbvh.qntx

# The page loads, the door comes up, and what the launch cost is over before
# anything is counted: a window that includes the load reads high.
sleep 45

# What the screen is showing, kept: a number about the door is only about the
# door if the door is what is there.
mkdir -p idle-samples
xcrun simctl io "$UDID" screenshot "idle-samples/$NAME.png"

# Three windows of twenty seconds, one after the other: each over the fifteen
# WebKit asks for, and a spike in one does not decide it. Under 3% passes, and
# a run that does not is kept all the same.
set +e
python3 ci/app-idle/sample.py "$UDID" "$NAME" 3 20
STATUS=$?
set -e
exit "$STATUS"
