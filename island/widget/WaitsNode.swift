import Foundation
import SacredError

// A press is run by the system in the app's process, never in the widget's:
// the widget draws the press and names it. This stands where the app's own
// asking of the node stands (island/app/WaitsNode.swift), so that the press
// 「[Opus 5.5] compiles here too. A press that did run here is a failure, and is sent.」

func waitsNodeIsAsked(_ path: String, _ sent: [String: Any]) async throws {
  throw Island.failed(
    "a press ran in the widget", "\(path) is asked from the app's process, and this is the widget's", region: "press")
}

// 「[Opus 5.5] The steps the app says to the node are the app's: the widget has none to say.」
func waitsIsSeen(_ what: String) {}

func waitsIsHeard(_ what: String) async {}
