import SwiftRs
import Tauri
import UIKit
import WebKit

// What this process uses, read the way WebKit reads its own: memory as
// phys_footprint from TASK_VM_INFO (WTF::memoryFootprint), CPU time as the time
// of threads that ended (MACH_TASK_BASIC_INFO) plus the time of threads that are
// running (TASK_THREAD_TIMES_INFO). This is the app's process: the page is in
// the web view's own process, and is not in these.
private func memoryFootprint() -> UInt64? {
  var info = task_vm_info_data_t()
  var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
  let result = withUnsafeMutablePointer(to: &info) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
    }
  }
  return result == KERN_SUCCESS ? info.phys_footprint : nil
}

private func seconds(_ time: time_value_t) -> Double {
  return Double(time.seconds) + Double(time.microseconds) / 1_000_000
}

private func cpuSeconds() -> Double? {
  var ended = mach_task_basic_info_data_t()
  var endedCount = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
  let endedResult = withUnsafeMutablePointer(to: &ended) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(endedCount)) {
      task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &endedCount)
    }
  }
  var running = task_thread_times_info_data_t()
  var runningCount = mach_msg_type_number_t(MemoryLayout<task_thread_times_info_data_t>.size / MemoryLayout<integer_t>.size)
  let runningResult = withUnsafeMutablePointer(to: &running) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(runningCount)) {
      task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), $0, &runningCount)
    }
  }
  guard endedResult == KERN_SUCCESS, runningResult == KERN_SUCCESS else { return nil }
  return seconds(ended.user_time) + seconds(ended.system_time) + seconds(running.user_time) + seconds(running.system_time)
}

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
        "memoryFootprint": memoryFootprint(),
        "cpuSeconds": cpuSeconds(),
      ])
    }
  }
}

@_cdecl("init_power")
func initPlugin() -> Plugin {
  return Power()
}
