#!/usr/bin/env bash
# The app as the phone runs it, booted in the iPhone Simulator, with the native
# chat opened by the page (probe.html) and shown two messages. Passes when the
# screen shows the chat (its title, Probe) with both messages, read off the
# screenshot by Tesseract, and the app is still running forty seconds after
# launch; the screen and what was read are kept. (What the plugin logs reaches
# neither the app's console nor `simctl spawn log show`, and macOS's Vision
# stops on this runner with nilError.)
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

bash ci/sim-ready.sh
xcrun simctl terminate "$UDID" nl.sbvh.qntx || true
xcrun simctl uninstall "$UDID" nl.sbvh.qntx || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" nl.sbvh.qntx
sleep 40

mkdir -p chat-shots
xcrun simctl io "$UDID" screenshot --display=1 chat-shots/opened.png || xcrun simctl io "$UDID" screenshot chat-shots/opened.png
command -v tesseract > /dev/null || brew install tesseract
tesseract chat-shots/opened.png chat-shots/read
cat chat-shots/read.txt
for shown in "Probe" "Hello from the probe" "And an answer"; do
  grep -qF "$shown" chat-shots/read.txt || { echo "the screen does not show: $shown"; exit 1; }
done
echo "the screen shows the native chat, Probe, with both messages"

if pgrep -f "$UDID.*QNTX.app/QNTX" > /dev/null; then
  echo "the app is running, forty seconds after launch, with the native chat opened"
else
  echo "the app is gone"
  exit 1
fi
