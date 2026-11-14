# 「[Fable 5.2, Opus 5.5] island」

「[Fable 5.2, Opus 5.5] What waits on a person, on the island, the lock screen and the Mac's menu」
「[Fable 5.2, Opus 5.5] bar. The story is the node's:」
「[Fable 5.2, Opus 5.5] [ADR-060](https://github.com/teranos/QNTX/blob/main/docs/adr/ADR-060-What-Waits-On-A-Person-Is-A-Live-Activity.md).」
「[Fable 5.2, Opus 5.5] This is what the app holds of it.」

## 「[Fable 5.2, Opus 5.5] Three folders, two targets」

| Folder | Compiled into | Holds |
|---|---|---|
| `shared/` | the app and the widget | `WaitsAttributes`, the one shape, and `PressWaits`, a press |
| `app/` | the app | the tokens handed to the node, and the node asked outside the page |
| `widget/` | the widget | what is drawn |

「[Fable 5.2, Opus 5.5] `.github/scripts/ios-project.py` adds them to the generated Xcode project.」
「[Fable 5.2, Opus 5.5] None of it is a Tauri plugin: a plugin's Swift is built outside Xcode, and the」
「[Fable 5.2, Opus 5.5] system runs a press only when it finds it among what Xcode compiled into the」
「[Fable 5.2, Opus 5.5] app.」

## 「[Fable 5.2, Opus 5.5] The node says, the app draws」

「[Fable 5.2, Opus 5.5] `WaitsAttributes` is decoded by the system from what the node sends」
「[Fable 5.2, Opus 5.5] (teranos/QNTX `server/phones.go`, `waitsOf` and `waitsShown`): the two are one」
「[Fable 5.2, Opus 5.5] shape, key for key, and a key one side has and the other lacks is a Live」
「[Fable 5.2, Opus 5.5] Activity that does not start. A new kind of thing that waits is the node's to」
「[Fable 5.2, Opus 5.5] add, and nothing here changes for it.」

「[Fable 5.2, Opus 5.5] A press is drawn as its mark and never as a word. `markOf` is the one place a」
「[Fable 5.2, Opus 5.5] press is given its mark.」

## 「[Fable 5.2, Opus 5.5] The app's main is not this repo's」

「[Fable 5.2, Opus 5.5] Tauri generates it. `app/WaitsBoot.m` is loaded with the app's image and」
「[Fable 5.2, Opus 5.5] begins handing over tokens once the app has launched, also when Apple launched」
「[Fable 5.2, Opus 5.5] it in the background for a Live Activity that started.」

## 「[Fable 5.2, Opus 5.5] The session」

「[Fable 5.2, Opus 5.5] The app's page is at another site than the node, so its session is no cookie:」
「[Fable 5.2, Opus 5.5] the page holds it and presents it on each request. `app/WaitsNode.swift`」
「[Fable 5.2, Opus 5.5] presents the same, read from the page while it is there and kept in the」
「[Fable 5.2, Opus 5.5] Keychain for when the system runs the app with no page. No token is made.」

## 「[Fable 5.2, Opus 5.5] What it does is in the node's log」

「[Fable 5.2, Opus 5.5] Each step is said to the node, in the place a client names itself:」
「[Fable 5.2, Opus 5.5] `QNTX-waits/<build>` and what happened. On the node:」

```
「[Fable 5.2, Opus 5.5] journalctl -u qntx | grep QNTX-waits」
```

## 「[Fable 5.2, Opus 5.5] What has stood on a phone」

「[Fable 5.2, Opus 5.5] On 2026-11-13 Live Activities stood on an iPhone and a Mac, started by the」
「[Fable 5.2, Opus 5.5] node with the app closed, and a press on one merged its pull request. On」
「[Fable 5.2, Opus 5.5] 2026-11-14 a collection pending for a session stood, with its countdown and」
「[Fable 5.2, Opus 5.5] three marks. ADR-060 holds the times, what is settled and what is not built.」
