#!/usr/bin/env bash
# An iPhone Simulator on iOS 26, as the phone runs, booted; its UDID into $GITHUB_ENV.
#
# Not iOS 27: built with the iOS 27 SDK, UIKit stops the app at launch there
# (_UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption), since Tauri's
# shell has not adopted the scene lifecycle. The xcode-27 runners differ in
# which runtimes they carry: an iPhone on iOS 26 is used when there is one,
# made from an iOS 26 runtime when there is that, and the runtime downloaded
# when there is neither.
set -euo pipefail

pick() {
  xcrun simctl list devices available -j | jq -r '[.devices | to_entries[] | select(.key | contains("iOS-26")) | .key as $rt | .value[] | select((.name | startswith("iPhone")) and (.name | contains("Duo") | not)) | {rt: $rt, udid}] | sort_by(.rt) | last | .udid'
}
runtime() {
  xcrun simctl list runtimes available -j | jq -r '[.runtimes[] | select(.platform == "iOS" and (.version | startswith("26.")))] | sort_by(.version) | last | .identifier'
}

UDID=$(pick)
if [ "$UDID" = "null" ] || [ -z "$UDID" ]; then
  RUNTIME=$(runtime)
  if [ "$RUNTIME" = "null" ] || [ -z "$RUNTIME" ]; then
    echo "no iOS 26 runtime on this runner: downloading iOS 26.2"
    xcodebuild -downloadPlatform iOS -buildVersion 26.2
    RUNTIME=$(runtime)
  fi
  test "$RUNTIME" != "null"
  TYPE=$(xcrun simctl list devicetypes -j | jq -r '[.devicetypes[] | select(.name | test("^iPhone 1[67]( Pro)?$"))] | last | .identifier')
  UDID=$(xcrun simctl create "QNTX iPhone" "$TYPE" "$RUNTIME")
fi
echo "iPhone: $UDID"
echo "UDID=$UDID" >> "$GITHUB_ENV"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
