#!/usr/bin/env bash
# An iPhone Simulator on the newest iOS the runner carries, booted; its UDID into
# $GITHUB_ENV. The app launches on iOS 27 since it declares the scene lifecycle
# (Info.ios.plist, Tauri 2.12). One display: the iPhone Duo has two, and a
# screenshot of it cannot choose. The runtime is the newest that can run the
# iPhone (Xcode 27.2 carries a Duo-only runtime beside the generic one); an
# iPhone already on it is used, or one is made on it.
set -euo pipefail

TYPE=$(xcrun simctl list devicetypes -j | jq -r '[.devicetypes[] | select(.name | test("^iPhone 1[67]( Pro)?$"))] | last | .identifier')
if [ "$TYPE" = "null" ] || [ -z "$TYPE" ]; then
  echo "::error::this runner's Xcode has no iPhone 16 or 17 device type"
  xcrun simctl list devicetypes
  exit 1
fi

RUNTIME=$(xcrun simctl list runtimes available -j | jq -r --arg type "$TYPE" '[.runtimes[] | select(.platform == "iOS") | select(any(.supportedDeviceTypes[]?; .identifier == $type))] | sort_by(.version | split(".") | map(tonumber)) | last | .identifier')
if [ "$RUNTIME" = "null" ] || [ -z "$RUNTIME" ]; then
  echo "::error::this runner carries no iOS Simulator runtime that runs $TYPE"
  xcrun simctl list runtimes
  exit 1
fi
echo "runtime: $RUNTIME"

UDID=$(xcrun simctl list devices available -j | jq -r --arg rt "$RUNTIME" '[.devices[$rt][]? | select((.name | startswith("iPhone")) and (.name | contains("Duo") | not))] | last | .udid')
if [ "$UDID" = "null" ] || [ -z "$UDID" ]; then
  UDID=$(xcrun simctl create "QNTX iPhone" "$TYPE" "$RUNTIME")
fi
echo "iPhone: $UDID"
echo "UDID=$UDID" >> "$GITHUB_ENV"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
