#!/usr/bin/env bash
# An iPhone Simulator on the newest iOS the runner carries, booted; its UDID into
# $GITHUB_ENV. The app launches on iOS 27 since it declares the scene lifecycle
# (Info.ios.plist, Tauri 2.12). One display: the iPhone Duo has two, and a
# screenshot of it cannot choose. An iPhone is made from the newest runtime when
# the runner has none.
set -euo pipefail

pick() {
  xcrun simctl list devices available -j | jq -r '[.devices | to_entries[] | select(.key | contains("iOS")) | .key as $rt | .value[] | select((.name | startswith("iPhone")) and (.name | contains("Duo") | not)) | {rt: $rt, udid}] | sort_by(.rt) | last | .udid'
}
runtime() {
  xcrun simctl list runtimes available -j | jq -r '[.runtimes[] | select(.platform == "iOS")] | sort_by(.version) | last | .identifier'
}

UDID=$(pick)
if [ "$UDID" = "null" ] || [ -z "$UDID" ]; then
  RUNTIME=$(runtime)
  if [ "$RUNTIME" = "null" ] || [ -z "$RUNTIME" ]; then
    echo "::error::this runner carries no iOS Simulator runtime"
    xcrun simctl list runtimes
    exit 1
  fi
  TYPE=$(xcrun simctl list devicetypes -j | jq -r '[.devicetypes[] | select(.name | test("^iPhone 1[67]( Pro)?$"))] | last | .identifier')
  UDID=$(xcrun simctl create "QNTX iPhone" "$TYPE" "$RUNTIME")
fi
echo "iPhone: $UDID"
echo "UDID=$UDID" >> "$GITHUB_ENV"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
