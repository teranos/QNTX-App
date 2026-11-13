import SwiftRs
import Tauri
import UIKit
import WebKit

#if canImport(ActivityKit)
import ActivityKit
#endif

struct CheckArgs: Decodable {
  let name: String
  let state: String
}

struct StartArgs: Decodable {
  let pullRequest: String
  let title: String
  let says: String
  let checks: [CheckArgs]
}

struct MoveArgs: Decodable {
  let id: String
  let says: String
  let checks: [CheckArgs]
}

// "the magic island": an approval as a Live Activity, started, moved and ended
// from the page. The island itself is drawn by the widget in island/widget.
class Island: Plugin {
  @objc public func start(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(StartArgs.self)
    #if canImport(ActivityKit)
    guard #available(iOS 16.1, *) else {
      invoke.reject("the island needs iOS 16.1, and this is \(UIDevice.current.systemVersion)")
      return
    }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      invoke.reject("Live Activities are turned off for QNTX in Settings")
      return
    }
    let attributes = IslandAttributes(pullRequest: args.pullRequest, title: args.title)
    let state = IslandAttributes.ContentState(says: args.says, checks: checksOf(args.checks))
    do {
      let activity = try Activity.request(attributes: attributes, contentState: state)
      invoke.resolve(["id": activity.id])
    } catch {
      invoke.reject("the island for \(args.pullRequest) did not start: \(error.localizedDescription)")
    }
    #else
    invoke.reject("the island needs ActivityKit, which this build has not")
    #endif
  }

  @objc public func update(_ invoke: Invoke) throws {
    try move(invoke, ending: false)
  }

  @objc public func end(_ invoke: Invoke) throws {
    try move(invoke, ending: true)
  }

  private func move(_ invoke: Invoke, ending: Bool) throws {
    let args = try invoke.parseArgs(MoveArgs.self)
    #if canImport(ActivityKit)
    guard #available(iOS 16.1, *) else {
      invoke.reject("the island needs iOS 16.1, and this is \(UIDevice.current.systemVersion)")
      return
    }
    guard let activity = Activity<IslandAttributes>.activities.first(where: { $0.id == args.id }) else {
      invoke.reject("no island \(args.id)")
      return
    }
    let state = IslandAttributes.ContentState(says: args.says, checks: checksOf(args.checks))
    Task {
      if ending {
        // What it ended as stays on the lock screen a moment, then goes.
        await activity.end(using: state, dismissalPolicy: .default)
      } else {
        await activity.update(using: state)
      }
      invoke.resolve()
    }
    #else
    invoke.reject("the island needs ActivityKit, which this build has not")
    #endif
  }
}

#if canImport(ActivityKit)
private func checksOf(_ checks: [CheckArgs]) -> [IslandCheck] {
  checks.map { IslandCheck(name: $0.name, state: $0.state) }
}
#endif

@_cdecl("init_island")
func initPlugin() -> Plugin {
  return Island()
}
