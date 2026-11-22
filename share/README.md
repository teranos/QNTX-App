# 「[Fable 5.2] Screenshot sharing: App-side handoff」

「[Fable 5.2] A person selects screenshots in Photos or another app, chooses QNTX in the」
「[Fable 5.2] share sheet, optionally says what they like, and presses Save. The extension」
「[Fable 5.2] copies the files into `group.nl.sbvh.qntx/ShareInbox`. The person then opens QNTX」
「[Fable 5.2] to choose an agent. Nothing is sent automatically. The share sheet does not」
「[Fable 5.2] try to launch the containing app through an unsupported responder-chain trick.」

「[Fable 5.2] This PR implements **iOS capture, persistence, and the native bridge**. It does」
「[Fable 5.2] not yet implement the QNTX-Web inbox/agent chooser or multi-image agent requests.」
「[Fable 5.2] Until that consumer exists, leave `IOS_SHARE_EXTENSION` disabled: the extension」
「[Fable 5.2] would save screenshots that the current frontend does not expose.」

## 「[Fable 5.2] Frontend contract」

「[Fable 5.2] Only the bundled main webview has `share:default`. There is no remote capability.」
「[Fable 5.2] The commands reject on unsupported platforms and when the App Group is missing.」

```ts
「[Fable 5.2] const { invoke } = window.__TAURI__.core;」
「[Fable 5.2] const { batches } = await invoke('plugin:share|pending');」
「[Fable 5.2] // batches: { id, createdAt: unixMilliseconds, note, images: [」
「[Fable 5.2] //   { id, name, mime: 'image/png' | 'image/jpeg', bytes }」
「[Fable 5.2] // ] }[]」
「[Fable 5.2] const image = await invoke('plugin:share|read_image', {」
  「[Fable 5.2] id: batch.id, imageId: batch.images[0].id,」
「[Fable 5.2] });」
「[Fable 5.2] // image: { mime, base64 } — one image at a time, not an entire batch over IPC.」
「[Fable 5.2] await invoke('plugin:share|acknowledge', { id: batch.id });」
```

「[Fable 5.2] Read pending batches after frontend startup and whenever the app returns to the」
「[Fable 5.2] foreground (`visibilitychange` when visible). Polling a persistent inbox avoids」
「[Fable 5.2] losing a share to a startup event that fires before the frontend is listening.」
「[Fable 5.2] Listing and reading are repeatable and never delete anything. Acknowledge only」
「[Fable 5.2] when the frontend has durably imported the batch, after confirmed delivery, or」
「[Fable 5.2] when the person explicitly discards it. A cancelled chooser or failed upload」
「[Fable 5.2] must retain it. Acknowledgement retries are idempotent.」

「[Fable 5.2] Keep `batch.id` as the import/delivery identity. A crash after server acceptance」
「[Fable 5.2] and before acknowledgement can otherwise send twice: frontend durable receipts」
「[Fable 5.2] or a server idempotency key are required before automatic retries. Agent choice」
「[Fable 5.2] must use the current node, account and namespace permissions, not remembered」
「[Fable 5.2] credentials from a different login. Nothing here stores an agent identifier.」

「[Fable 5.2] The optional note is user text. Original source-app identity and originating」
「[Fable 5.2] URLs are **not** supplied reliably by this image share API and are not invented.」
「[Fable 5.2] Filenames are display metadata; storage uses generated IDs, never supplied paths.」

## 「[Fable 5.2] Limits and failure behavior」

「[Fable 5.2] Up to 10 PNG/JPEG images, 10 MiB each, 50 MiB per batch, and 16 KiB of note text.」
「[Fable 5.2] The extension checks the actual ImageIO image type, not just the declared MIME.」
「[Fable 5.2] Files load sequentially and are copied before provider temporary URLs expire.」
「[Fable 5.2] No full-resolution bitmap decode or screenshot re-encoding is needed.」

「[Fable 5.2] A hidden staging directory becomes a visible batch through one rename only」
「[Fable 5.2] after every image and its manifest are written. Normal import failures remove」
「[Fable 5.2] the draft and show a native error; cleanup failures are reported too. If iOS」
「[Fable 5.2] kills the extension during import, its hidden staging directory is not offered」
「[Fable 5.2] as a partial batch. Such interrupted staging files remain until app data is」
「[Fable 5.2] removed; a later retention policy can reclaim them. Completed batches remain」
「[Fable 5.2] until explicit acknowledgement/discard. There is no automatic age-based deletion.」

## 「[Fable 5.2] Signing and release activation」

1. 「[Fable 5.2] Register App Group `group.nl.sbvh.qntx` for both `nl.sbvh.qntx` and the new」
   「[Fable 5.2] extension identifier `nl.sbvh.qntx.share` in the Apple developer account.」
2. 「[Fable 5.2] Regenerate the host distribution profile with that App Group and update the」
   「[Fable 5.2] existing `IOS_MOBILE_PROVISION` secret / `PROVISIONING_PROFILE` variable.」
3. 「[Fable 5.2] Create an App Store distribution profile for `nl.sbvh.qntx.share`. Add its」
   「[Fable 5.2] base64 contents as `IOS_SHARE_MOBILE_PROVISION`, and its exact name as the」
   「[Fable 5.2] repository variable `SHARE_PROVISIONING_PROFILE`. It uses the existing team」
   「[Fable 5.2] and distribution certificate.」
4. 「[Fable 5.2] After the frontend consumer is available, set `IOS_SHARE_EXTENSION=true`.」

「[Fable 5.2] The existing TestFlight workflow then installs/validates the extension profile,」
「[Fable 5.2] adds an embedded `QNTXShare` target to Tauri's generated XcodeGen project, and」
「[Fable 5.2] adds the App Group while retaining host entitlements. Both bundles use the」
「[Fable 5.2] same version/build. Native registration is present even when the extension is」
「[Fable 5.2] disabled; no inbox access occurs until the frontend asks for it.」

「[Fable 5.2] Tauri CLI 2.11.4 supplies only the host's provisioning profile during export and」
「[Fable 5.2] shallow-merges ExportOptions. Enabled builds therefore use `--archive-only`,」
「[Fable 5.2] then `xcodebuild -exportArchive` with an explicit mapping for **both** bundles.」
「[Fable 5.2] The archive must contain `QNTXShare.appex` before export. Disabled builds follow」
「[Fable 5.2] the existing Tauri export path. Sources are in `ci/testflight.nix` and the」
「[Fable 5.2] checked-in workflow; edits must keep them aligned.」

## 「[Fable 5.2] Validation」

「[Fable 5.2] `python3 .github/scripts/test-ios-share-project.py` checks generated-project」
「[Fable 5.2] changes, existing entitlements, repeatability, and missing signing settings.」
「[Fable 5.2] On macOS, `bash .github/scripts/check-share-native.sh` runs the Swift storage」
「[Fable 5.2] tests and builds the actual Share Extension for the simulator without signing.」
「[Fable 5.2] The `Screenshot share` PR workflow runs those checks. The normal app build」
「[Fable 5.2] checks the Rust/Tauri bridge and its Swift package integration.」

「[Fable 5.2] Before enabling for testers, verify on an iPhone with the frontend consumer:」

- 「[Fable 5.2] Share one screenshot, then several; preserve order, bytes and note.」
- 「[Fable 5.2] Share while QNTX is terminated; opening it finds the batch. Repeat with it」
  「[Fable 5.2] already running, signed out, and offline.」
- 「[Fable 5.2] Cancel the agent chooser and restart: screenshots remain. Choose a different」
  「[Fable 5.2] agent and verify the destination before sending.」
- 「[Fable 5.2] Reject an unsupported image or an oversized selection without publishing a」
  「[Fable 5.2] partial batch. Exercise a provider failure and a storage failure.」
- 「[Fable 5.2] After successful durable import/delivery, acknowledge exactly that batch;」
  「[Fable 5.2] other batches remain. Retry acknowledgement and replay a completed batch ID.」
- 「[Fable 5.2] Verify the signed IPA embeds the extension and both profiles carry the group.」

「[Fable 5.2] Architecture references: [Apple Share Extensions](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html),」
「[Fable 5.2] [shared containers and activation rules](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html),」
「[Fable 5.2] [Tauri mobile plugins](https://v2.tauri.app/develop/plugins/develop-mobile/).」
