import ActivityKit
import SwiftUI
import UIKit
import os

let said = Logger(subsystem: "nl.sbvh.probe", category: "probe")

// Registered with Apple's push service, as the island is at launch
// (QNTX-App island/app/WaitsTokens.swift): whether the Simulator gives a
// device token, and a token to start Live Activities by, is part of the answer.
final class ProbeDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    application.registerForRemoteNotifications()
    return true
  }

  func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
    said.log("PROBE device token bytes=\(token.count, privacy: .public)")
  }

  func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    said.log("PROBE device token refused: \(String(describing: error), privacy: .public)")
  }
}

@main
struct ProbeApp: App {
  @UIApplicationDelegateAdaptor(ProbeDelegate.self) var delegate

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
