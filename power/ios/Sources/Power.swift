import SwiftRs
import Tauri
import UIKit
import WebKit

// What the phone says about its own power, at the moment it is asked.
class Power: Plugin {
  // "The default value of this property is false, which disables the ability
  // to read battery charge level and battery state."
  // https://developer.apple.com/documentation/uikit/uidevice/isbatterymonitoringenabled
  override func load(webview: WKWebView) {
    UIDevice.current.isBatteryMonitoringEnabled = true
  }

  @objc public func read(_ invoke: Invoke) throws {
    DispatchQueue.main.async {
      let device = UIDevice.current
      let process = ProcessInfo.processInfo

      let battery: String
      switch device.batteryState {
      case .unknown: battery = "unknown"
      case .unplugged: battery = "unplugged"
      case .charging: battery = "charging"
      case .full: battery = "full"
      @unknown default: battery = "unrecognised"
      }

      let thermal: String
      switch process.thermalState {
      case .nominal: thermal = "nominal"
      case .fair: thermal = "fair"
      case .serious: thermal = "serious"
      case .critical: thermal = "critical"
      @unknown default: thermal = "unrecognised"
      }

      // batteryLevel is 0.0 to 1.0, and -1.0 while the battery state is unknown.
      invoke.resolve([
        "batteryLevel": Double(device.batteryLevel),
        "batteryState": battery,
        "lowPowerMode": process.isLowPowerModeEnabled,
        "thermalState": thermal,
      ])
    }
  }
}

@_cdecl("init_power")
func initPlugin() -> Plugin {
  return Power()
}
