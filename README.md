# QNTX App

The shell QNTX runs inside on a phone and a desktop. A WKWebView on iOS, a
WebView on Android, a window on macOS — and in every case the thing you look at
is QNTX's own frontend, built from QNTX main and carried inside the bundle.

## It does not build alone

There are no crates here and no frontend. Both come from
[QNTX](https://github.com/teranos/QNTX), checked out at `qntx/` beside this, at
main. `Cargo.toml` and `frontendDist` both reach across into it. QNTX knows
nothing of this repo; this repo is what reaches over.

```
git clone https://github.com/teranos/QNTX qntx
```

## When it builds

On every push here, and on dispatch. Either way it carries QNTX main as it is
at that moment.

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
back into the app. That is `plugins/ceremony`: one command, `run`. Off iOS
the command says there is no sheet, and the door opens Safari and waits for
the `qntx://` deep link instead.

## What the pipeline proves

A run is green when App Store Connect says a tester can install the build,
not when the upload returned. Export compliance is answered in
`Info.ios.plist`; without it a build sits unanswered and reaches nobody.
`.github/scripts/delivered.py` is the asking.

## What signs it

An Apple distribution certificate and an App Store provisioning profile, held
as secrets here. A build lands in TestFlight and updates itself from there.
