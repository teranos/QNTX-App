#!/usr/bin/env bash
# The island drawn in the iPhone Simulator. Run from ci/island-draw with $UDID
# a booted iPhone: builds the host (project.yml), launches it, reads from the
# system log that the island's Live Activity started and stands active, puts
# the app in the background so the island is what is drawn, and keeps a
# screenshot of it in seen/.
set -euxo pipefail

xcodegen generate
xcodebuild build -project IslandDraw.xcodeproj -scheme IslandDraw -configuration Release -sdk iphonesimulator \
  -destination "id=$UDID" -derivedDataPath dd -quiet ENABLE_DEBUG_DYLIB=NO
APP=dd/Build/Products/Release-iphonesimulator/IslandDraw.app

xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" nl.sbvh.islanddraw.app
sleep 10
# In the background, what stands is drawn on the island and the lock screen.
xcrun simctl launch "$UDID" com.apple.Preferences
sleep 5

mkdir -p seen
xcrun simctl io "$UDID" screenshot seen/island.png
xcrun simctl spawn "$UDID" log show --last 5m --style compact --predicate 'subsystem == "nl.sbvh.islanddraw"' > seen/log.txt
grep -F "DRAW" seen/log.txt

grep -q -F "DRAW started" seen/log.txt
grep -q -F "DRAW standing=1 states=active says=2 wait" seen/log.txt
