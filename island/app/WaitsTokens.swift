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
// so the newest of each is kept, and what the node has not taken is handed
// over again when the app comes to the front and every half minute until it has.
@objc(WaitsTokens)
final class WaitsTokens: NSObject {
  // The newest token of each, in hex, by what it is of: empty for the phone's
  // own, and what a started activity is of for that activity's. A token Apple
  // renews takes the place of the one before it.
  private static var newest: [String: String] = [:]
  // What the node has taken, as newest holds it.
  private static var taken: [String: String] = [:]
  private static let turn = DispatchQueue(label: "waits.tokens")
  private static var begun = false
  private static var again: Task<Void, Never>?

  @objc static func begin() {
    guard #available(iOS 17.2, *) else { return }
    guard !begun else { return }
    begun = true
    waitsIsSeen("begun activities=\(ActivityAuthorizationInfo().areActivitiesEnabled) starts=\(Activity<WaitsAttributes>.pushToStartToken != nil)")

    // Apple gives the token to start by to an app that is registered with its
    // push service, and not always to one that is not: said in Apple's own
    // answers on its forums (threads 835188, 761214), and in no documentation.
    // What Apple hands the app's delegate for it is of another kind and is
    // not used; the registering is what this is for.
    DispatchQueue.main.async {
      UIApplication.shared.registerForRemoteNotifications()
    }
    // The sequence below says a token Apple made later, and not always one it
    // made before anybody listened: it is read again after a moment, and again.
    Task {
      for wait in [3, 15, 60, 300] as [UInt64] {
        try? await Task.sleep(nanoseconds: wait * 1_000_000_000)
        let has = Activity<WaitsAttributes>.pushToStartToken != nil
        waitsIsSeen("after-\(wait)s starts=\(has)")
        await handAll()
        if has { return }
        if wait == 15 { await startOneHere() }
      }
    }
    Task {
      for await token in Activity<WaitsAttributes>.pushToStartTokenUpdates {
        waitsIsSeen("apple-gave-a-token-to-start-by")
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

  // What the one this phone starts by itself is of: nothing on the node, and the node is told nothing of it.
  private static let ofThisPhone = "phone/reached"

  // Apple gave this phone no token to start by. Developers on Apple's forums
  // say Apple gives one to an app that has started a Live Activity itself
  // (threads 761214, 741939); Apple's documentation says it need not. So,
  // once, with the app in front, one is started here and ended: it says the
  // phone is reached by the node, which it is once Apple gives the token.
  @available(iOS 17.2, *)
  private static func startOneHere() async {
    let inFront = await MainActor.run { UIApplication.shared.applicationState == .active }
    guard inFront else {
      waitsIsSeen("not-in-front none-started-here")
      return
    }
    let of = WaitsAttributes(waits: ofThisPhone, kind: "this phone", title: "")
    let shows = WaitsAttributes.ContentState(says: "reached by your node", preview: "", due: 0, segments: [], presses: [])
    do {
      let one = try Activity<WaitsAttributes>.request(
        attributes: of, content: ActivityContent(state: shows, staleDate: nil), pushType: .token)
      waitsIsSeen("started-one-here")
      try? await Task.sleep(nanoseconds: 8_000_000_000)
      await one.end(ActivityContent(state: shows, staleDate: nil), dismissalPolicy: .immediate)
    } catch {
      waitsIsSeen("none-started-here: \(error.localizedDescription)")
    }
  }

  @available(iOS 17.2, *)
  private static func follow(_ activity: Activity<WaitsAttributes>) {
    let waits = activity.attributes.waits
    if waits == ofThisPhone { return }
    Task {
      // The token it has already, which the sequence below may never say again.
      if let token = activity.pushToken {
        await hand(token, of: waits)
      }
      for await token in activity.pushTokenUpdates {
        await hand(token, of: waits)
      }
      // Over: nothing of it is handed over again.
      turn.sync {
        newest[waits] = nil
        taken[waits] = nil
      }
    }
  }

  private static func hex(_ token: Data) -> String {
    token.map { String(format: "%02x", $0) }.joined()
  }

  private static func hand(_ token: Data, of waits: String) async {
    turn.sync { newest[waits] = hex(token) }
    await handAll()
  }

  // Hands the node each newest token it has not taken, and tries again in
  // half a minute while one is left: the person may log in with the app open.
  private static func handAll() async {
    if #available(iOS 17.2, *), let starts = Activity<WaitsAttributes>.pushToStartToken {
      turn.sync { newest[""] = hex(starts) }
    }
    let owed = turn.sync { newest.filter { taken[$0.key] != $0.value } }
    if owed.isEmpty, turn.sync(execute: { newest.isEmpty }) {
      var enabled = false
      if #available(iOS 17.2, *) { enabled = ActivityAuthorizationInfo().areActivitiesEnabled }
      waitsIsSeen("in-front no-token-from-apple-yet activities=\(enabled)")
    }
    var left = false
    for (waits, token) in owed {
      if await say(token, of: waits) {
        turn.sync { taken[waits] = token }
      } else {
        left = true
      }
    }
    guard left else { return }
    turn.sync {
      again?.cancel()
      again = Task {
        try? await Task.sleep(nanoseconds: 30_000_000_000)
        guard !Task.isCancelled else { return }
        await handAll()
      }
    }
  }

  private static func say(_ token: String, of waits: String) async -> Bool {
    var sent = ["token": token, "platform": "ios"]
    if !waits.isEmpty {
      sent["waits"] = waits
      // Which phone it stands on, by the token this phone starts them by:
      // the node starts on another phone what does not stand there.
      if let phone = turn.sync(execute: { newest[""] }) {
        sent["phone"] = phone
      }
    }
    do {
      try await waitsNodeIsAsked("/api/phones", sent)
      return true
    } catch {
      NSLog("[Waits] the node was not handed a token: %@", error.localizedDescription)
      waitsIsSeen("not-handed \(waits.isEmpty ? "start" : "activity") token: \(error.localizedDescription)")
      return false
    }
  }
}
