import ActivityKit
import SwiftUI
import os
let said = Logger(subsystem: "nl.sbvh.probe", category: "probe")
@main
struct ProbeApp: App {
  init() {
    said.log("PROBE launched enabled=\(ActivityAuthorizationInfo().areActivitiesEnabled, privacy: .public) standing=\(Activity<ProbeAttributes>.activities.count, privacy: .public)")
    Task {
      for await token in Activity<ProbeAttributes>.pushToStartTokenUpdates {
        said.log("PROBE push-to-start token bytes=\(token.count, privacy: .public)")
      }
    }
    Task {
      for await started in Activity<ProbeAttributes>.activityUpdates {
        said.log("PROBE activity started id=\(started.id, privacy: .public) says=\(started.content.state.says, privacy: .public)")
      }
    }
  }
  var body: some Scene { WindowGroup { Text("probe") } }
}
