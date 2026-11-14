import Foundation

// 「[Fable 5.2, Opus 5.5] A press is run by the system in the app's process, never in the widget's:」
// 「[Fable 5.2, Opus 5.5] the widget draws the press and names it. This stands where the app's own」
// 「[Fable 5.2, Opus 5.5] asking of the node stands (island/app/WaitsNode.swift), so that the press」
// 「[Fable 5.2, Opus 5.5] compiles here too.」
struct WaitsNodeRefused: LocalizedError {
  let says: String
  var errorDescription: String? { says }
}

func waitsNodeIsAsked(_ path: String, _ sent: [String: Any]) async throws {
  throw WaitsNodeRefused(says: "a press is answered in the app, and this is the widget")
}

func waitsIsSeen(_ what: String) {}
