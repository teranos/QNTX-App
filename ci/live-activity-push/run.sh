#!/usr/bin/env bash
# 「[Opus 5.5] Whether a Live Activity is started in the iPhone Simulator by a push, as the」
# 「[Opus 5.5] node starts one on a phone through Apple. simctl's own help says it pushes」
# 「[Opus 5.5] only application remote push notifications: this is the run that says」
# 「[Opus 5.5] whether a push with event start starts one all the same. If it does, the」
# 「[Opus 5.5] island's tests start what they test the way the node does.」
#
# 「[Opus 5.5] A probe app of its own, so nothing of QNTX decides the answer: one Live」
# 「[Opus 5.5] Activity type, a widget that draws it, and a log line for each thing」
# 「[Opus 5.5] ActivityKit says. Run from this directory, with $UDID a booted iPhone.」
set -euxo pipefail

xcodegen generate
# What the build was told to sign with, said before it builds.
xcodebuild -showBuildSettings -project Probe.xcodeproj -scheme Probe -sdk iphonesimulator \
  | grep -F -e CODE_SIGN_ENTITLEMENTS -e CODE_SIGN_IDENTITY -e CODE_SIGNING_ALLOWED -e ENABLE_DEBUG_DYLIB
# Release, and no debug library beside the executable: what is signed is the one binary.
xcodebuild build -project Probe.xcodeproj -scheme Probe -configuration Release -sdk iphonesimulator \
  -destination "id=$UDID" -derivedDataPath dd -quiet ENABLE_DEBUG_DYLIB=NO
APP=dd/Build/Products/Release-iphonesimulator/Probe.app
# Built for the Simulator with aps-environment, as the island is signed with
# it. A Simulator build carries its entitlements in the binary's
# __TEXT,__entitlements section, not in its signature: both are said, and the
# run goes on only when one of them holds it.
set +e
codesign -d --entitlements - "$APP" > seen-signature.txt 2>&1
echo "codesign exited $?"
set -e
cat seen-signature.txt
grep -r -a -l -F aps-environment "$APP" | tee seen-section.txt
if ! grep -q -F aps-environment seen-signature.txt && [ ! -s seen-section.txt ]; then
  echo "the probe was built without aps-environment"
  exit 1
fi

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

# 「[Opus 5.5] The answer: a Live Activity started by the push, or none.」
if grep -q -F "PROBE activity started" seen/log.txt; then
  echo "A push with event start started a Live Activity in the Simulator."
else
  echo "No Live Activity was started by the push in the Simulator."
  exit 1
fi
