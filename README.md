# QNTX App

The shell QNTX runs inside on a phone and a desktop. A WKWebView on iOS, a
WebView on Android, a window on macOS — and in every case the thing you look at
is QNTX's own frontend, built from a tag and carried inside the bundle.

## It does not build alone

There are no crates here and no frontend. Both come from
[QNTX](https://github.com/teranos/QNTX), checked out at `qntx/` beside this, at
the tag being built. `Cargo.toml` and `frontendDist` both reach across into it.

```
git clone https://github.com/teranos/QNTX qntx
```

## What signs it

An Apple distribution certificate and an App Store provisioning profile, held
as secrets here. A build lands in TestFlight and updates itself from there.
