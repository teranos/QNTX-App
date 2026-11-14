# QNTX App

The shell QNTX runs inside on a phone and a desktop. A WKWebView on iOS, a
WebView on Android, a window on macOS — and in every case the thing you look at
is QNTX's own frontend, built from QNTX-Web main and carried inside the bundle.

## It does not build alone

There are no crates here and no frontend. The crates come from
[QNTX](https://github.com/teranos/QNTX), checked out at `qntx/` beside this, at
main; `Cargo.toml` reaches across into it, and the version is its `git
describe`. The frontend comes from [QNTX-Web](https://github.com/teranos/QNTX-Web),
checked out at `qntx-web/`, at main; `frontendDist` is its `dist/`. Neither knows
of this repo; this repo is what reaches over.

```
git clone https://github.com/teranos/QNTX qntx
git clone https://github.com/teranos/QNTX-Web qntx-web
```

## When it builds

On every push here, and on dispatch. Either way it carries QNTX main and
QNTX-Web main as they are at that moment.

「[Fable 5.2, Opus 5.5] A build reaches a phone from main, or when somebody dispatched it. A push to」
「[Fable 5.2, Opus 5.5] any other branch builds, signs and proves itself, and is not uploaded.」

> 「[Fable 5.2, Opus 5.5] WHY DID I SEE LIKE 10 TESTFLIGHT BUILDS WHEN I WAS WALKING」

## What version it is

QNTX's newest release tag, with the run number as the build. The workflow
writes the version into `tauri.conf.json` before the build. What was actually
built is `git describe` on main, and that is the release an event in Sentry
names.

## What the store requires of the door

Guideline 4.8: an app that signs people in with Google must also offer Sign
in with Apple. The node offers Apple wherever it offers Google, so the App
does.

## How the door reaches a provider

The app's page is at a scheme, so a provider's page inside its WebView has no
Safari session, no autofill and no passkey. On iOS the ceremony runs in the
sheet the system gives a web sign-in, `ASWebAuthenticationSession`, which is
backed by Safari's cookies and passkeys and hands the callback URL straight
back into the app. That is `sheet/`: one command, `run`. Not a plugin in
the QNTX sense, nothing runs beside the node; it is the App's own Swift,
registered the way Tauri registers native code. Off iOS the command says
there is no sheet, and the door opens Safari and waits for the `qntx://` deep
link instead.

## The shake, and the snapshot it carries

> think ROOT SHAKE

> i want to shake my phone and talk to an element

> feel a shake without permission? create an agent that makes us have it

> and snapshot of course

That is `shake/`, native like `sheet/`. The phone's own accelerometer says
when it is shaken, CoreMotion on iOS and SensorManager on Android, and neither
sits behind a prompt. Each shake reaches the page as the Tauri event `shake`,
payload `{ "at": <unix ms> }`:
`window.__TAURI__.event.listen('shake', ...)`. One command, `snapshot`,
hands the page what the web view shows:
`window.__TAURI__.core.invoke('plugin:shake|snapshot')` resolves
`{ "png": "data:image/png;base64,...", "width": n, "height": n }`, pixels.
Off a phone there is no shake, and `snapshot` says it is unsupported.

## 「[Fable 5.2, Opus 5.5] What waits on a person stands on the island」

> 「[Fable 5.2, Opus 5.5] the magic island」

> 「[Fable 5.2, Opus 5.5] THE BATCH IS A LIVE ACTIVITY」

「[Fable 5.2, Opus 5.5] That is `island/`. The node starts it, says all it shows and ends it; the app」
「[Fable 5.2, Opus 5.5] draws it, hands the node the tokens Apple gives it, and answers a press. The」
「[Fable 5.2, Opus 5.5] story, what a press is and what it rests on are the node's to say:」
「[Fable 5.2, Opus 5.5] [ADR-060](https://github.com/teranos/QNTX/blob/main/docs/adr/ADR-060-What-Waits-On-A-Person-Is-A-Live-Activity.md).」
「[Fable 5.2, Opus 5.5] What is the app's own is in [island/README.md](island/README.md).」

## What the pipeline proves

A run is green when App Store Connect says a tester can install the build,
not when the upload returned. Export compliance is answered in
`Info.ios.plist`; without it a build sits unanswered and reaches nobody.
`.github/scripts/delivered.py` is the asking.

「[Fable 5.2, Opus 5.5] Before anything is uploaded, the build reads back from the app it made what」
「[Fable 5.2, Opus 5.5] that app is: where the node is, that it may have Live Activities, that it」
「[Fable 5.2, Opus 5.5] carries the island and its press, and what it is signed as being allowed」
「[Fable 5.2, Opus 5.5] (`.github/scripts/export-island-ipa.py`). What was written into the project」
「[Fable 5.2, Opus 5.5] is not what Apple reads, and an app signed without `aps-environment` is not」
「[Fable 5.2, Opus 5.5] uploaded.」

## What signs it

An Apple distribution certificate and an App Store provisioning profile, held
as secrets here. A build lands in TestFlight and updates itself from there.

「[Fable 5.2, Opus 5.5] The island is its own bundle, signed by its own profile. Apple is asked for」
「[Fable 5.2, Opus 5.5] its App ID and profile with the key CI holds, and each is made where missing」
「[Fable 5.2, Opus 5.5] (`.github/workflows/island-apple.yml`); the profile is the secret」
「[Fable 5.2, Opus 5.5] `IOS_ISLAND_MOBILE_PROVISION`.」

TestFlight is the build that counts. The Android build (`ci/android.nix`)
waits: it runs only when dispatched by hand.

"the android build isnt critical now"

## Screenshots shared from another iPhone app

`share/` receives PNG/JPEG screenshots through an iOS Share Extension. A batch
keeps the selected order and an optional note in an App Group container until
QNTX's frontend explicitly acknowledges it. The extension saves locally and
asks the person to choose their agent in QNTX; it never guesses a recipient or
uploads under a cached identity.

This is the App-side handoff. The frontend inbox/agent chooser and multiple-image
agent submission are follow-up work. Distribution stays disabled until that
consumer and the App Group provisioning are ready. See [share/README.md](share/README.md)
for the bridge, signing setup, and device acceptance checks. Android receiving
is not implemented by this iOS increment.
