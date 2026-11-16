import ActivityKit
import SwiftUI
import os

// What the island draws, started as the node starts it, in the Simulator:
// a collection waiting for an agent, shaped as the node shapes one
// (teranos/QNTX server/phones.go, batchShown), with its three presses.
// Each step is said in the system log, where run.sh reads it.
private let said = Logger(subsystem: "nl.sbvh.islanddraw", category: "draw")

@main
struct DrawApp: App {
  init() {
    Task { @MainActor in
      said.log("DRAW enabled=\(ActivityAuthorizationInfo().areActivitiesEnabled, privacy: .public)")
      let to = ["to": "did:key:z6MkBirchBirchBirchBirchBirchBirchBirchBirch"]
      let seen = to.merging(["drawn": "drawn-with-two"]) { one, _ in one }
      let state = WaitsAttributes.ContentState(
        says: "2 wait",
        preview: "Alder: pull request one is open\nHazel: the pond is drained",
        due: Date().addingTimeInterval(6 * 3600).timeIntervalSince1970,
        segments: [],
        presses: [
          WaitsPress(says: "send now", does: "approve", then: "sent", path: "/api/collected/release", sent: seen, armed: false),
          WaitsPress(says: "delay", does: "delay", then: "delayed", path: "/api/collected/later", sent: to, armed: false),
          WaitsPress(says: "cancel", does: "cancel", then: "canceled", path: "/api/collected/cancel", sent: seen, armed: true),
        ])
      do {
        let started = try Activity.request(
          attributes: WaitsAttributes(waits: "collected/" + (to["to"] ?? ""), kind: "collected", title: "for Birch"),
          content: ActivityContent(state: state, staleDate: nil))
        said.log("DRAW started id=\(started.id, privacy: .public) state=\(String(describing: started.activityState), privacy: .public)")
      } catch {
        said.log("DRAW not started: \(String(describing: error), privacy: .public)")
      }
      try? await Task.sleep(nanoseconds: 3_000_000_000)
      let standing = Activity<WaitsAttributes>.activities
      said.log("DRAW standing=\(standing.count, privacy: .public) states=\(standing.map { String(describing: $0.activityState) }.joined(separator: ","), privacy: .public) says=\(standing.first?.content.state.says ?? "", privacy: .public)")
    }
  }

  var body: some Scene {
    WindowGroup { Text("the island is drawn") }
  }
}
