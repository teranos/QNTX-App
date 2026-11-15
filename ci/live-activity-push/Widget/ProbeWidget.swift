import ActivityKit
import SwiftUI
import WidgetKit
@main
struct ProbeWidgets: WidgetBundle { var body: some Widget { ProbeLive() } }
struct ProbeLive: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: ProbeAttributes.self) { c in Text(c.state.says) } dynamicIsland: { c in
      DynamicIsland { DynamicIslandExpandedRegion(.center) { Text(c.state.says) } } compactLeading: { Text("P") } compactTrailing: { Text(c.state.says) } minimal: { Text("P") }
    }
  }
}
