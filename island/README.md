# island

What waits on a person, on the island, the lock screen and the Mac's menu
bar. The story is the node's:
[ADR-060](https://github.com/teranos/QNTX/blob/main/docs/adr/ADR-060-What-Waits-On-A-Person-Is-A-Live-Activity.md).
This is what the app holds of it.

## Three folders, two targets

| Folder | Compiled into | Holds |
|---|---|---|
| `shared/` | the app and the widget | `WaitsAttributes`, the one shape, and `PressWaits`, a press |
| `app/` | the app | the tokens handed to the node, and the node asked outside the page |
| `widget/` | the widget | what is drawn |

`.github/scripts/ios-project.py` adds them to the generated Xcode project.
None of it is a Tauri plugin: a plugin's Swift is built outside Xcode, and the
system runs a press only when it finds it among what Xcode compiled into the
app.

## The node says, the app draws

`WaitsAttributes` is decoded by the system from what the node sends
(teranos/QNTX `server/phones.go`, `waitsOf` and `waitsShown`): the two are one
shape, key for key, and a key one side has and the other lacks is a Live
Activity that does not start. A new kind of thing that waits is the node's to
add, and nothing here changes for it.

A press is drawn as its mark and never as a word. `markOf` is the one place a
press is given its mark.

## The app's main is not this repo's

Tauri generates it. `app/WaitsBoot.m` is loaded with the app's image and
begins handing over tokens once the app has launched, also when Apple launched
it in the background for a Live Activity that started.

## The session

The app's page is at another site than the node, so its session is no cookie:
the page holds it and presents it on each request. `app/WaitsNode.swift`
presents the same, read from the page while it is there and kept in the
Keychain for when the system runs the app with no page. No token is made.

## What it does is in the node's log

Each step is said to the node, in the place a client names itself:
`QNTX-waits/<build>` and what happened. On the node:

```
journalctl -u qntx | grep QNTX-waits
```

## What has stood on a phone

On 2026-11-13 Live Activities stood on an iPhone and a Mac, started by the
node with the app closed, and a press on one merged its pull request. On
2026-11-14 a collection pending for a session stood, with its countdown and
three marks. ADR-060 holds the times, what is settled and what is not built.
