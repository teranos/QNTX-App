#!/usr/bin/env bash
# The booted iPhone ready again after a build: on the xcode-27 runners the
# Simulator service has been found dead after xcodebuild ("CoreSimulatorService:
# Connection interrupted"), and every simctl after it failed. The service is
# started afresh and the iPhone ($UDID) booted again.
set -euo pipefail
killall -9 com.apple.CoreSimulator.CoreSimulatorService 2>/dev/null || true
sleep 3
xcrun simctl list devices > /dev/null
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
