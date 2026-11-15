#!/usr/bin/env bash
# Whether a Live Activity is started in the iPhone Simulator by a push, as the
# node starts one on a phone through Apple. simctl's own help says it pushes
# only application remote push notifications: this is the run that says
# whether a push with event start starts one all the same. If it does, the
# island's tests start what they test the way the node does.
#
# A probe app of its own, so nothing of QNTX decides the answer: one Live
# Activity type, a widget that draws it, and a log line for each thing
# ActivityKit says. Run from this directory, with $UDID a booted iPhone.
set -euxo pipefail

xcodegen generate
xcodebuild build -project Probe.xcodeproj -scheme Probe -sdk iphonesimulator \
  -destination "id=$UDID" -derivedDataPath dd CODE_SIGNING_ALLOWED=NO -quiet
APP=dd/Build/Products/Debug-iphonesimulator/Probe.app

xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" nl.sbvh.probe.app
sleep 10

NOW=$(date +%s)
cat > start.apns <<JSON
{
  "Simulator Target Bundle": "nl.sbvh.probe.app",
  "aps": {
    "timestamp": $NOW,
    "event": "start",
    "content-state": { "says": "started by a push" },
    "attributes-type": "ProbeAttributes",
    "attributes": { "name": "probe" },
    "alert": { "title": "probe", "body": "started by a push" }
  }
}
JSON
set +e
xcrun simctl push "$UDID" nl.sbvh.probe.app start.apns
echo "simctl push exited $?"
set -e
sleep 15

mkdir -p seen
xcrun simctl io "$UDID" screenshot seen/after-push.png
xcrun simctl spawn "$UDID" log show --last 5m --style compact \
  --predicate 'subsystem == "nl.sbvh.probe" OR ((process == "chronod" OR process == "liveactivitiesd" OR process == "SpringBoard") AND eventMessage CONTAINS[c] "activit")' \
  > seen/log.txt
grep -F "PROBE" seen/log.txt

# The answer: a Live Activity started by the push, or none.
if grep -q -F "PROBE activity started" seen/log.txt; then
  echo "A push with event start started a Live Activity in the Simulator."
else
  echo "No Live Activity was started by the push in the Simulator."
  exit 1
fi
