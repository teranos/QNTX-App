import ActivityKit
import AppIntents
import Foundation

// A press on what waits, answered where it stands: on the island, the lock
// screen, or the Mac's menu bar, without the app being opened. The system
// runs it in the app's process, and it asks the node what the press says to
// ask, in the session the app is in: no token is made for it (QNTX-App #11).
//
// It is named by the activity it was pressed on and the place of the press
// among its presses, and what it asks is read from what the activity shows
// now: the node said it, and a press carries nothing of its own to ask.
@available(iOS 17.2, *)
struct PressWaits: LiveActivityIntent {
  static var title: LocalizedStringResource = "Answer what waits"
  static var isDiscoverable: Bool = false

  @Parameter(title: "What waits")
  var activity: String

  @Parameter(title: "The press")
  var press: Int

  init() {}

  init(activity: String, press: Int) {
    self.activity = activity
    self.press = press
  }

  func perform() async throws -> some IntentResult {
    guard let stands = Activity<WaitsAttributes>.activities.first(where: { $0.id == activity }) else {
      return .result()
    }
    let shown = stands.content.state
    guard shown.presses.indices.contains(press) else {
      return .result()
    }
    let pressed = shown.presses[press]

    // Pressed: nothing more is pressed while the node is asked.
    var asking = shown
    asking.presses = []
    asking.says = pressed.says + "…"
    await stands.update(ActivityContent(state: asking, staleDate: nil))

    do {
      try await waitsNodeIsAsked(pressed.path, pressed.sent)
      // Done: it says what became of it, and leaves in a minute.
      var done = asking
      done.says = pressed.then
      done.due = 0
      await stands.end(
        ActivityContent(state: done, staleDate: nil),
        dismissalPolicy: .after(Date().addingTimeInterval(60)))
    } catch {
      // Not done: it says so, and its presses are there to press again.
      var failed = shown
      failed.says = "\(pressed.says) was not done: \(error.localizedDescription)"
      await stands.update(ActivityContent(state: failed, staleDate: nil))
    }
    return .result()
  }
}
