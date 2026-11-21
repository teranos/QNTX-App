# Screenshot sharing: App-side handoff

A person selects screenshots in Photos or another app, chooses QNTX in the
share sheet, optionally says what they like, and presses Save. The extension
copies the files into `group.nl.sbvh.qntx/ShareInbox`. The person then opens QNTX
to choose an agent. Nothing is sent automatically. The share sheet does not
try to launch the containing app through an unsupported responder-chain trick.

This PR implements **iOS capture, persistence, and the native bridge**. It does
not yet implement the QNTX-Web inbox/agent chooser or multi-image agent requests.
Until that consumer exists, leave `IOS_SHARE_EXTENSION` disabled: the extension
would save screenshots that the current frontend does not expose.

## Frontend contract

Only the bundled main webview has `share:default`. There is no remote capability.
The commands reject on unsupported platforms and when the App Group is missing.

```ts
const { invoke } = window.__TAURI__.core;
const { batches } = await invoke('plugin:share|pending');
// batches: { id, createdAt: unixMilliseconds, note, images: [
//   { id, name, mime: 'image/png' | 'image/jpeg', bytes }
// ] }[]
const image = await invoke('plugin:share|read_image', {
  id: batch.id, imageId: batch.images[0].id,
});
// image: { mime, base64 } — one image at a time, not an entire batch over IPC.
await invoke('plugin:share|acknowledge', { id: batch.id });
```

Read pending batches after frontend startup and whenever the app returns to the
foreground (`visibilitychange` when visible). Polling a persistent inbox avoids
losing a share to a startup event that fires before the frontend is listening.
Listing and reading are repeatable and never delete anything. Acknowledge only
when the frontend has durably imported the batch, after confirmed delivery, or
when the person explicitly discards it. A cancelled chooser or failed upload
must retain it. Acknowledgement retries are idempotent.

Keep `batch.id` as the import/delivery identity. A crash after server acceptance
and before acknowledgement can otherwise send twice: frontend durable receipts
or a server idempotency key are required before automatic retries. Agent choice
must use the current node, account and namespace permissions, not remembered
credentials from a different login. Nothing here stores an agent identifier.

The optional note is user text. Original source-app identity and originating
URLs are **not** supplied reliably by this image share API and are not invented.
Filenames are display metadata; storage uses generated IDs, never supplied paths.

## Limits and failure behavior

Up to 10 PNG/JPEG images, 10 MiB each, 50 MiB per batch, and 16 KiB of note text.
The extension checks the actual ImageIO image type, not just the declared MIME.
Files load sequentially and are copied before provider temporary URLs expire.
No full-resolution bitmap decode or screenshot re-encoding is needed.

A hidden staging directory becomes a visible batch through one rename only
after every image and its manifest are written. Normal import failures remove
the draft and show a native error; cleanup failures are reported too. If iOS
kills the extension during import, its hidden staging directory is not offered
as a partial batch. Such interrupted staging files remain until app data is
removed; a later retention policy can reclaim them. Completed batches remain
until explicit acknowledgement/discard. There is no automatic age-based deletion.

## Signing and release activation

1. Register App Group `group.nl.sbvh.qntx` for both `nl.sbvh.qntx` and the new
   extension identifier `nl.sbvh.qntx.share` in the Apple developer account.
2. Regenerate the host distribution profile with that App Group and update the
   existing `IOS_MOBILE_PROVISION` secret / `PROVISIONING_PROFILE` variable.
3. Create an App Store distribution profile for `nl.sbvh.qntx.share`. Add its
   base64 contents as `IOS_SHARE_MOBILE_PROVISION`, and its exact name as the
   repository variable `SHARE_PROVISIONING_PROFILE`. It uses the existing team
   and distribution certificate.
4. After the frontend consumer is available, set `IOS_SHARE_EXTENSION=true`.

The existing TestFlight workflow then installs/validates the extension profile,
adds an embedded `QNTXShare` target to Tauri's generated XcodeGen project, and
adds the App Group while retaining host entitlements. Both bundles use the
same version/build. Native registration is present even when the extension is
disabled; no inbox access occurs until the frontend asks for it.

Tauri CLI 2.11.4 supplies only the host's provisioning profile during export and
shallow-merges ExportOptions. Enabled builds therefore use `--archive-only`,
then `xcodebuild -exportArchive` with an explicit mapping for **both** bundles.
The archive must contain `QNTXShare.appex` before export. Disabled builds follow
the existing Tauri export path. Sources are in `ci/testflight.nix` and the
checked-in workflow; edits must keep them aligned.

## Validation

`python3 .github/scripts/test-ios-share-project.py` checks generated-project
changes, existing entitlements, repeatability, and missing signing settings.
On macOS, `bash .github/scripts/check-share-native.sh` runs the Swift storage
tests and builds the actual Share Extension for the simulator without signing.
The `Screenshot share` PR workflow runs those checks. The normal app build
checks the Rust/Tauri bridge and its Swift package integration.

Before enabling for testers, verify on an iPhone with the frontend consumer:

- Share one screenshot, then several; preserve order, bytes and note.
- Share while QNTX is terminated; opening it finds the batch. Repeat with it
  already running, signed out, and offline.
- Cancel the agent chooser and restart: screenshots remain. Choose a different
  agent and verify the destination before sending.
- Reject an unsupported image or an oversized selection without publishing a
  partial batch. Exercise a provider failure and a storage failure.
- After successful durable import/delivery, acknowledge exactly that batch;
  other batches remain. Retry acknowledgement and replay a completed batch ID.
- Verify the signed IPA embeds the extension and both profiles carry the group.

Architecture references: [Apple Share Extensions](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html),
[shared containers and activation rules](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html),
[Tauri mobile plugins](https://v2.tauri.app/develop/plugins/develop-mobile/).
