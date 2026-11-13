import Foundation

// A press is run by the system in the app's process, never in the widget's:
// the widget draws the press and names it. This stands where the app's own
// asking of the node stands (island/app/WaitsNode.swift), so that the press
// compiles here too.
struct WaitsNodeRefused: LocalizedError {
  let says: String
  var errorDescription: String? { says }
}

func waitsNodeIsAsked(_ path: String, _ sent: [String: String]) async throws {
  throw WaitsNodeRefused(says: "a press is answered in the app, and this is the widget")
}

func waitsIsSeen(_ what: String) {}
