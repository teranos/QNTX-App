import ActivityKit
import AppIntents
import Foundation

// 「[Fable 5.2, Opus 5.5] A press on what waits, answered where it stands: on the island, the lock」
// 「[Fable 5.2, Opus 5.5] screen, or the Mac's menu bar, without the app being opened. The system」
// 「[Fable 5.2, Opus 5.5] runs it in the app's process, and it asks the node what the press says to」
// 「[Fable 5.2, Opus 5.5] ask, in the session the app is in: no token is made for it.」
//
// 「[Fable 5.2, Opus 5.5] It is named by the activity it was pressed on, the place of the press among」
// 「[Fable 5.2, Opus 5.5] its presses, and what that press asked when it was drawn. What it asks is」
// 「[Fable 5.2, Opus 5.5] read from what the activity shows now, for the node said it, and it is」
// 「[Fable 5.2, Opus 5.5] asked only when that is still what was drawn: the node may have moved what」
// 「[Fable 5.2, Opus 5.5] stands between the drawing and the press, and a press never asks what the」
// 「[Fable 5.2, Opus 5.5] person did not see.」
@available(iOS 17.2, *)
struct PressWaits: LiveActivityIntent {
  static var title: LocalizedStringResource = "Answer what waits"
  static var isDiscoverable: Bool = false

  @Parameter(title: "What waits")
  var activity: String

  @Parameter(title: "The press")
  var press: Int

  @Parameter(title: "What it asks")
  var asks: String

  init() {}

  init(activity: String, press: Int, asks: String) {
    self.activity = activity
    self.press = press
    self.asks = asks
  }

  func perform() async throws -> some IntentResult {
    // 「[Fable 5.2, Opus 5.5] A press does what a person decided: every way it ends is said, where」
    // 「[Fable 5.2, Opus 5.5] the person sees it and where the node writes it down.」
    guard let stands = Activity<WaitsAttributes>.activities.first(where: { $0.id == activity }) else {
      waitsIsSeen("press-not-done nothing-stands-as \(activity) asked=\(asks)")
      throw WaitsPressNotDone(says: "what was pressed no longer stands")
    }
    let shown = stands.content.state
    guard shown.presses.indices.contains(press), shown.presses[press].asks == asks else {
      // 「[Fable 5.2, Opus 5.5] What stands changed under the finger: nothing is asked, and it says so.」
      waitsIsSeen("press-not-done it-changed of=\(stands.attributes.waits) asked=\(asks)")
      var changed = shown
      changed.says = "it changed: press again"
      await stands.update(ActivityContent(state: changed, staleDate: nil))
      return .result()
    }
    let pressed = shown.presses[press]
    // 「[Fable 5.2, Opus 5.5] One press of one thing at a time: a second tap before the first is」
    // 「[Fable 5.2, Opus 5.5] answered asks the node nothing.」
    guard PressesInHand.take(activity) else {
      waitsIsSeen("press-not-done already-asking of=\(stands.attributes.waits)")
      return .result()
    }
    defer { PressesInHand.give(activity) }
    waitsIsSeen("pressed \(pressed.does) of=\(stands.attributes.waits)")

    // 「[Fable 5.2, Opus 5.5] Pressed: nothing more is pressed while the node is asked.」
    var asking = shown
    asking.presses = []
    asking.says = pressed.says + "…"
    await stands.update(ActivityContent(state: asking, staleDate: nil))

    do {
      try await waitsNodeIsAsked(pressed.path, pressed.sent)
      waitsIsSeen("press-done \(pressed.does) of=\(stands.attributes.waits)")
      // 「[Fable 5.2, Opus 5.5] Done: it says what became of it and leaves. What was delayed leaves at」
      // 「[Fable 5.2, Opus 5.5] once, for it is not over: the node starts it again for the wait」
      // 「[Fable 5.2, Opus 5.5] before its new time. What was sent or canceled leaves in a minute.」
      // "WHEN DELAY CANT WE MAKE IT BE DISMISSED UNTIL ITS TIME TO SHOW AGAIN /"
      var done = asking
      done.says = pressed.then
      done.due = 0
      await stands.end(
        ActivityContent(state: done, staleDate: nil),
        dismissalPolicy: pressed.does == "delay" ? .immediate : .after(Date().addingTimeInterval(60)))
    } catch {
      // 「[Fable 5.2, Opus 5.5] Not done: it says so. What the node said meanwhile stands; where it」
      // 「[Fable 5.2, Opus 5.5] said nothing, the presses are there to press again.」
      waitsIsSeen("press-not-done \(pressed.does) of=\(stands.attributes.waits): \(error.localizedDescription)")
      var failed = stands.content.state == asking ? shown : stands.content.state
      failed.says = "\(pressed.says) was not done: \(error.localizedDescription)"
      await stands.update(ActivityContent(state: failed, staleDate: nil))
    }
    return .result()
  }
}

// 「[Fable 5.2, Opus 5.5] What is being asked of the node now, by the activity it was pressed on.」
enum PressesInHand {
  private static var asking: Set<String> = []
  private static let turn = NSLock()

  static func take(_ activity: String) -> Bool {
    turn.lock()
    defer { turn.unlock() }
    return asking.insert(activity).inserted
  }

  static func give(_ activity: String) {
    turn.lock()
    asking.remove(activity)
    turn.unlock()
  }
}

struct WaitsPressNotDone: LocalizedError {
  let says: String
  var errorDescription: String? { says }
}

extension WaitsPress {
  // 「[Fable 5.2, Opus 5.5] What the press asks of the node, as one thing to compare: the path, and what is sent there.」
  var asks: String {
    path + "?" + sent.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
  }
}
