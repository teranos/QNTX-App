import CoreMotion
import SwiftRs
import Tauri
import UIKit
import WebKit

struct WatchArgs: Decodable {
  let handler: Channel
}

// CoreMotion, not UIResponder.motionEnded: the responder chain runs through a
// view controller Tauri generates into gen/apple on every build, where nothing
// of this repo can sit. The accelerometer asks nothing of the responder chain.
class Shake: Plugin {
  private var webview: WKWebView?
  private let motion = CMMotionManager()
  private let readings = OperationQueue()
  private var lastShakeAt: TimeInterval = 0

  // In g: the accelerometer reads 1 at rest, gravity alone. Android reads the
  // same number, so a shake is the same shake on both.
  private let shakeG = 2.7
  private let debounce: TimeInterval = 0.5

  override func load(webview: WKWebView) {
    self.webview = webview
  }

  @objc public func watch(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(WatchArgs.self)
    guard motion.isAccelerometerAvailable else {
      invoke.reject("no accelerometer on this device")
      return
    }
    readings.maxConcurrentOperationCount = 1
    motion.accelerometerUpdateInterval = 1.0 / 60.0
    motion.startAccelerometerUpdates(to: readings) { data, _ in
      guard let a = data?.acceleration else { return }
      let g = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
      if g < self.shakeG { return }
      let now = Date().timeIntervalSince1970
      if now - self.lastShakeAt < self.debounce { return }
      self.lastShakeAt = now
      let shaken: JsonObject = ["at": Int64(now * 1000)]
      args.handler.send(shaken)
    }
    invoke.resolve()
  }

  @objc public func snapshot(_ invoke: Invoke) {
    DispatchQueue.main.async {
      guard let webview = self.webview else {
        invoke.reject("the web view is not loaded yet")
        return
      }
      webview.takeSnapshot(with: nil) { image, error in
        if let error = error {
          invoke.reject("the snapshot failed: \(error.localizedDescription)")
          return
        }
        guard let image = image, let png = image.pngData() else {
          invoke.reject("the snapshot has no image")
          return
        }
        invoke.resolve([
          "png": "data:image/png;base64," + png.base64EncodedString(),
          "width": Int(image.size.width * image.scale),
          "height": Int(image.size.height * image.scale),
        ])
      }
    }
  }
}

@_cdecl("init_shake")
func initPlugin() -> Plugin {
  return Shake()
}
