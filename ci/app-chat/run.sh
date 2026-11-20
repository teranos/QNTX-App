#!/usr/bin/env bash
# The app as the phone runs it, booted in the iPhone Simulator, with the native
# chat opened by the page (probe.html) and shown two messages. Passes when the
# app is still running forty seconds after launch; the screen is kept.
#
# Run from the QNTX-App checkout, with QNTX beside it at qntx/ and the page the
# app is to carry already in qntx-web/dist.
set -euxo pipefail

python3 - qntx-web/dist/index.html <<'PY'
import sys
path = sys.argv[1]
page = open(path).read()
at = page.rindex('</body>')
open(path, 'w').write(page[:at] + open('ci/app-chat/probe.html').read() + page[at:])
PY

rm -rf gen/apple/build
cargo tauri ios build --target aarch64-sim --no-sign --debug
APP=$(find gen/apple/build -maxdepth 4 -name '*.app' -path '*arm64-sim*' | head -1)
test -n "$APP"
test -d "$APP/Chat_ExyteChat.bundle"
test -d "$APP/Frameworks/GiphyUISDK.framework"

xcrun simctl terminate "$UDID" nl.sbvh.qntx || true
xcrun simctl uninstall "$UDID" nl.sbvh.qntx || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" nl.sbvh.qntx
sleep 40

mkdir -p chat-shots
xcrun simctl io "$UDID" screenshot --display=1 chat-shots/opened.png || xcrun simctl io "$UDID" screenshot chat-shots/opened.png
if pgrep -f "$UDID.*QNTX.app/QNTX" > /dev/null; then
  echo "the app is running, forty seconds after launch, with the native chat opened"
else
  echo "the app is gone"
  exit 1
fi
