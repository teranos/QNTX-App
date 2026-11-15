import ActivityKit
import Foundation
import SacredError
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
// so the newest of each is kept, and what the node has not taken, or has not
// been told is over, is handed over again: when the app comes to the front, and after a wait that doubles
// each time it is refused, up to ten minutes.
@objc(WaitsTokens)
final class WaitsTokens: NSObject {
  // What is handed over for one thing: its token in hex, and what it is of.
  private struct Held: Equatable {
    var token: String
    var waits: String
  }

  // The phone's own is kept under this, beside each activity under its own id.
  private static let thePhone = ""

  // The newest of each, by the activity's id: two activities of the same
  // thing, one ending as the next begins, are two. A token Apple renews takes
  // the place of the one before it.
  private static var newest: [String: Held] = [:]
  // What the node has taken, as newest held it then, and what the phone's own
  // token and the session were when it took it: with another phone token or
  // another person in the app, it is handed over anew.
  private static var taken: [String: Held] = [:]
  private static var takenWith = ""
  // What is over and the node has not been told so yet, by the activity's id:
  // it is told until it takes it, as a token is handed until it is taken.
  private static var over: [String: Held] = [:]
  private static let turn = DispatchQueue(label: "waits.tokens")
  private static var begun = false
  private static var again: Task<Void, Never>?
  private static var refused = 0

  @objc static func begin() {
    guard #available(iOS 17.2, *) else { return }
    guard !begun else { return }
    begun = true
    // Begun on the main thread at launch, before anything of the island can fail.
    Island.start()
    waitsIsSeen("begun activities=\(ActivityAuthorizationInfo().areActivitiesEnabled) starts=\(Activity<WaitsAttributes>.pushToStartToken != nil)")

    // Apple gives the token to start by to an app that is registered with its
    // push service, and not always to one that is not: said in Apple's own
    // answers on its forums (thread 835188), and in no documentation. What
    // Apple hands the app's delegate for it is of another kind and is not
    // used; the registering is what this is for.
    DispatchQueue.main.async {
      UIApplication.shared.registerForRemoteNotifications()
    }
    // The sequence below says a token Apple made later, and before iOS 26 not
    // always one it made before anybody listened (Apple, forum thread
    // 799526): it is read again after a moment, and again.
    Task {
      for wait in [3, 15, 60] as [UInt64] {
        guard await pause(wait) else { return }
        let has = Activity<WaitsAttributes>.pushToStartToken != nil
        if !has { waitsIsSeen("after-\(wait)s no-token-from-apple") }
        await handAll()
        if has { return }
      }
    }
    Task {
      for await token in Activity<WaitsAttributes>.pushToStartTokenUpdates {
        waitsIsSeen("apple-gave-a-token-to-start-by")
        turn.sync { newest[thePhone] = Held(token: hex(token), waits: "") }
        await handAll()
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
      // In front again: asked at once, whatever was being waited for.
      turn.sync { refused = 0 }
      Task { await handAll() }
    }
  }

  @available(iOS 17.2, *)
  private static func follow(_ activity: Activity<WaitsAttributes>) {
    let id = activity.id
    let waits = activity.attributes.waits
    Task {
      // The token it has already, which the sequence below may never say again.
      if let token = activity.pushToken {
        turn.sync { newest[id] = Held(token: hex(token), waits: waits) }
        await handAll()
      }
      for await token in activity.pushTokenUpdates {
        turn.sync { newest[id] = Held(token: hex(token), waits: waits) }
        await handAll()
      }
      // Over: nothing of this one is handed over again, and the node is told
      // it no longer stands here, so that it starts what waits anew where it
      // would. Another of the same thing is another id.
      turn.sync {
        if let last = newest[id] { over[id] = last }
        newest[id] = nil
        taken[id] = nil
      }
      await handAll()
    }
  }

  private static func hex(_ token: Data) -> String {
    token.map { String(format: "%02x", $0) }.joined()
  }

  // The step the hand-over that runs now is at, by the pass it belongs to.
  private static var passes = 0
  private static var at: [Int: String] = [:]

  private static func reached(_ pass: Int, _ step: String) {
    turn.sync { at[pass] = step }
    Island.step(step, region: "tokens")
  }

  // Hands the node each newest token it has not taken. A pass that has not
  // ended a minute after it began is sent as a failure, naming the step it is
  // at: a hand-over that hangs fails nothing, and said nothing.
  private static func handAll() async {
    let pass: Int = turn.sync {
      passes += 1
      return passes
    }
    reached(pass, "began")
    let watched = Task {
      guard await pause(60) else { return }
      let stuck: String? = turn.sync { at[pass] }
      if let stuck = stuck {
        Island.failed(
          "a token hand-over did not end", "a minute after it began it is still at: \(stuck)", region: "tokens")
      }
    }
    defer {
      watched.cancel()
      turn.sync { at[pass] = nil }
    }
    if #available(iOS 17.2, *), let starts = Activity<WaitsAttributes>.pushToStartToken {
      turn.sync { newest[thePhone] = Held(token: hex(starts), waits: "") }
    }
    reached(pass, "asking who is in the app")
    // Who is in the app and which phone token stands: with either another, everything is owed anew.
    let with = await waitsSessionMark() + " " + (turn.sync { newest[thePhone]?.token ?? "" })
    reached(pass, "knows who is in the app")
    let owed: [String: Held] = turn.sync {
      if takenWith != with {
        taken = [:]
        takenWith = with
      }
      return newest.filter { taken[$0.key] != $0.value }
    }
    var left = false
    for (id, held) in owed {
      reached(pass, "handing over \(held.waits.isEmpty ? "the phone's token" : "the token of \(held.waits)")")
      if await say(held, gone: false) {
        // Taken as it was handed, by who was in the app then: one Apple
        // renewed meanwhile, or handed over as another person, is owed still.
        turn.sync { if newest[id] == held && takenWith == with { taken[id] = held } }
      } else {
        left = true
      }
    }
    // What is over is said until the node takes it: one it still holds as
    // standing here is one it does not start again.
    for (id, held) in turn.sync(execute: { over }) {
      reached(pass, "saying \(held.waits) is over")
      if await say(held, gone: true) {
        turn.sync { if over[id] == held { over[id] = nil } }
      } else {
        left = true
      }
    }
    let still = turn.sync { !over.isEmpty || newest.contains { taken[$0.key] != $0.value } }
    guard left || still else {
      turn.sync { refused = 0 }
      return
    }
    // Asked again after a wait that doubles, ten minutes at most: a person
    // may log in with the app open, and a node that keeps refusing is not
    // asked twice a minute for as long as the app is in front.
    let wait: UInt64 = turn.sync {
      refused += 1
      again?.cancel()
      let doubled = UInt64(30) << UInt64(min(refused - 1, 5))
      return min(UInt64(600), doubled)
    }
    let next = Task {
      guard await pause(wait) else { return }
      await handAll()
    }
    turn.sync { again = next }
  }

  private static func say(_ held: Held, gone: Bool) async -> Bool {
    var sent: [String: Any] = ["token": held.token, "platform": "ios"]
    if gone { sent["gone"] = true }
    if !held.waits.isEmpty {
      sent["waits"] = held.waits
      // Which phone it stands on, by the token this phone starts them by:
      // the node starts on another phone what does not stand there.
      if let phone = turn.sync(execute: { newest[thePhone]?.token }) {
        sent["phone"] = phone
      }
    }
    do {
      try await waitsNodeIsAsked("/api/phones", sent)
      return true
    } catch {
      // 「[Opus 5.5] What the node said is the SacredError waitsNodeIsAsked made and sent.」
      Island.failed("the node was not handed a token", from: error, region: "tokens")
      if turn.sync(execute: { refused }) == 0 {
        waitsIsSeen("not-handed \(held.waits.isEmpty ? "start" : "activity") token: \(error.localizedDescription)")
      }
      return false
    }
  }

  // 「[Opus 5.5] Waits seconds, and answers whether to go on: a wait that is called off is」
  // 「[Opus 5.5] over, and anything else that ends it is a failure, sent.」
  private static func pause(_ seconds: UInt64) async -> Bool {
    do {
      try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
      return true
    } catch is CancellationError {
      return false
    } catch {
      Island.failed("a wait ended early", from: error, region: "tokens")
      return false
    }
  }
}
