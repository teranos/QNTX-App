import ObjectiveC
import SwiftRs
import Tauri
import UIKit
import UserNotifications
import WebKit

// The token Apple gives this phone, for the node to reach it by: the node tells
// the phone what is about to be said to an agent, fifteen minutes before it is.
//
// Apple hands the token to the app's delegate, and the delegate is Tauri's,
// made at run time where nothing of this repo can sit. So the two methods
// Apple calls are added to the delegate's class, once, and the delegate is
// set again: UIKit asks a delegate what it answers to when it is set, and one
// that learned to answer afterwards is never asked.

// Who waits for the token, on the main thread only.
private var waiting: [Invoke] = []
private var hooked = false
private var hookFailed: String?

private func answer(token: String?, why: String?) {
  let asked = waiting
  waiting = []
  for invoke in asked {
    if let token = token {
      invoke.resolve(["token": token, "platform": "ios"])
    } else {
      invoke.reject(why ?? "Apple gave this phone no push token")
    }
  }
}

private func hook() {
  if hooked { return }
  hooked = true
  let app = UIApplication.shared
  guard let delegate = app.delegate else {
    hookFailed = "the app has no delegate for Apple to hand the token to"
    return
  }
  let kind: AnyClass = type(of: delegate)

  let registered: @convention(block) (AnyObject, UIApplication, Data) -> Void = { _, _, data in
    answer(token: data.map { String(format: "%02x", $0) }.joined(), why: nil)
  }
  let failed: @convention(block) (AnyObject, UIApplication, NSError) -> Void = { _, _, error in
    answer(token: nil, why: "Apple gave this phone no push token: \(error.localizedDescription)")
  }
  // v@:@@ is a method returning nothing that takes the application and one object.
  let tookToken = class_addMethod(
    kind,
    #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)),
    imp_implementationWithBlock(registered), "v@:@@")
  let tookFailure = class_addMethod(
    kind,
    #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:)),
    imp_implementationWithBlock(failed), "v@:@@")
  if !tookToken || !tookFailure {
    // The delegate already answers them: the token goes there, and never comes here.
    hookFailed = "the app's delegate already takes the push token, so it does not reach the page"
    return
  }
  app.delegate = nil
  app.delegate = delegate
}

class Push: Plugin {
  // The phone's token, asking the person for notifications the first time.
  @objc public func token(_ invoke: Invoke) {
    DispatchQueue.main.async {
      hook()
      if let why = hookFailed {
        invoke.reject(why)
        return
      }
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
        DispatchQueue.main.async {
          if let error = error {
            invoke.reject("notifications were not asked for: \(error.localizedDescription)")
            return
          }
          guard granted else {
            invoke.reject("notifications are turned off for QNTX in Settings")
            return
          }
          waiting.append(invoke)
          UIApplication.shared.registerForRemoteNotifications()
        }
      }
    }
  }
}

@_cdecl("init_push")
func initPlugin() -> Plugin {
  return Push()
}
