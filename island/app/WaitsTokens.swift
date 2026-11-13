import ActivityKit
import Foundation
import UIKit

// The tokens the node reaches Live Activities by, handed to it as Apple gives
// them: the phone's token for starting one, with the app closed, and the own
// token of each one that started, which moves and ends it. Apple gives them
// to the app's process, also when it starts the app in the background for a
// Live Activity that began, so this runs from the app's launch and needs no
// page (WaitsBoot.m begins it).
//
// The node takes them in the person's own session (teranos/QNTX
// server/phones.go, HandlePhone). Before the app is logged in it takes none,
// so each is kept and handed over again whenever the app comes to the front.
@objc(WaitsTokens)
final class WaitsTokens: NSObject {
  // What is handed over: the token in hex, and what the activity is of, empty for the phone's own.
  private static var held: [String: String] = [:]
  private static let turn = DispatchQueue(label: "waits.tokens")
  private static var begun = false

  @objc static func begin() {
    guard #available(iOS 17.2, *) else { return }
    guard !begun else { return }
    begun = true

    Task {
      for await token in Activity<WaitsAttributes>.pushToStartTokenUpdates {
        await hand(token, of: "")
      }
    }
    Task {
      for await started in Activity<WaitsAttributes>.activityUpdates {
        follow(started)
      }
    }
    for standing in Activity<WaitsAttributes>.activities {
      follow(standing)
    }
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil
    ) { _ in
      Task { await handAll() }
    }
  }

  @available(iOS 17.2, *)
  private static func follow(_ activity: Activity<WaitsAttributes>) {
    Task {
      for await token in activity.pushTokenUpdates {
        await hand(token, of: activity.attributes.waits)
      }
    }
  }

  private static func hand(_ token: Data, of waits: String) async {
    let hex = token.map { String(format: "%02x", $0) }.joined()
    turn.sync { held[hex] = waits }
    await say(hex, of: waits)
  }

  private static func handAll() async {
    if #available(iOS 17.2, *), let starts = Activity<WaitsAttributes>.pushToStartToken {
      await hand(starts, of: "")
    }
    let all = turn.sync { held }
    for (hex, waits) in all {
      await say(hex, of: waits)
    }
  }

  private static func say(_ hex: String, of waits: String) async {
    var sent = ["token": hex, "platform": "ios"]
    if !waits.isEmpty {
      sent["waits"] = waits
      // Which phone it stands on, by the token this phone starts them by:
      // the node starts on another phone what does not stand there.
      if #available(iOS 17.2, *), let starts = Activity<WaitsAttributes>.pushToStartToken {
        sent["phone"] = starts.map { String(format: "%02x", $0) }.joined()
      }
    }
    do {
      try await waitsNodeIsAsked("/api/phones", sent)
    } catch {
      NSLog("[Waits] the node was not handed a token: %@", error.localizedDescription)
    }
  }
}
