import ActivityKit
import SwiftUI
import WidgetKit

// The island an approval stands on: the compact pill, the view held open, and
// the lock screen. The presses come with #11; this draws what stands.
//
// QNTX's own look: near-black surfaces, the botanical green, JetBrains Mono's
// stand-in (the system monospace), SEG glyphs and no emoji.

private let accent = Color(red: 0x7d / 255, green: 0xba / 255, blue: 0x8a / 255)
private let onDark = Color(red: 0xdf / 255, green: 0xe1 / 255, blue: 0xe0 / 255)
private let onDarkSecondary = Color(red: 0xa9 / 255, green: 0xab / 255, blue: 0xaa / 255)
private let onDarkTertiary = Color(red: 0x86 / 255, green: 0x87 / 255, blue: 0x87 / 255)
private let surface = Color(red: 0x1a / 255, green: 0x1b / 255, blue: 0x1a / 255)

// The segment a check is drawn as.
private func colorOf(_ state: String) -> Color {
  switch state {
  case "done": return Color(red: 0x22 / 255, green: 0xc6 / 255, blue: 0x5e / 255)
  case "failed": return Color(red: 0xe4 / 255, green: 0x47 / 255, blue: 0x47 / 255)
  case "running": return Color(red: 0x63 / 255, green: 0x94 / 255, blue: 0xd5 / 255)
  default: return Color(red: 0x3f / 255, green: 0x41 / 255, blue: 0x40 / 255)
  }
}

private struct Segments: View {
  let checks: [IslandCheck]
  let width: CGFloat?
  let height: CGFloat

  var body: some View {
    HStack(spacing: 3) {
      ForEach(Array(checks.enumerated()), id: \.offset) { _, check in
        RoundedRectangle(cornerRadius: 1)
          .fill(colorOf(check.state))
          .frame(width: width, height: height)
      }
    }
    .accessibilityElement()
    .accessibilityLabel(summaryOf(checks))
  }
}

private func summaryOf(_ checks: [IslandCheck]) -> String {
  let drawn = ["done", "running", "failed"]
  let counts = drawn.map { state in (state, checks.filter { $0.state == state }.count) }
    + [("waiting", checks.filter { !drawn.contains($0.state) }.count)]
  return counts.filter { $0.1 > 0 }.map { "\($0.1) \($0.0)" }.joined(separator: " · ")
}

private let mono = Font.system(size: 11, design: .monospaced)

// The widget target deploys at iOS 16.1, where Live Activities begin.
struct IslandLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: IslandAttributes.self) { context in
      // The lock screen.
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text("꩜ qntx · approvals").font(mono).foregroundColor(onDarkTertiary)
          Spacer()
          Text(context.attributes.pullRequest).font(mono).foregroundColor(onDarkTertiary)
        }
        VStack(alignment: .leading, spacing: 3) {
          Text(context.state.says).font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
          Text(context.attributes.title).font(.system(size: 13)).foregroundColor(onDarkSecondary).lineLimit(1)
        }
        Segments(checks: context.state.checks, width: nil, height: 5)
        Text(summaryOf(context.state.checks)).font(.system(size: 10, design: .monospaced)).foregroundColor(onDarkTertiary)
      }
      .padding(16)
      .activityBackgroundTint(surface)
      .activitySystemActionForegroundColor(onDark)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text("꩜").font(.system(size: 16, design: .monospaced)).foregroundColor(accent)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(context.attributes.pullRequest).font(mono).foregroundColor(onDarkTertiary)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(context.state.says).font(.system(size: 15, weight: .semibold)).foregroundColor(.white).lineLimit(1)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 6) {
            Text(context.attributes.title).font(.system(size: 13)).foregroundColor(onDarkSecondary).lineLimit(1)
            ForEach(Array(context.state.checks.enumerated()), id: \.offset) { _, check in
              HStack {
                Text(check.name).font(mono).foregroundColor(onDark)
                Spacer()
                Text(check.state).font(mono).foregroundColor(colorOf(check.state))
              }
            }
          }
        }
      } compactLeading: {
        Text("꩜").font(.system(size: 14, design: .monospaced)).foregroundColor(accent)
      } compactTrailing: {
        Segments(checks: context.state.checks, width: 7, height: 4)
      } minimal: {
        Text("꩜").font(.system(size: 13, design: .monospaced)).foregroundColor(accent)
      }
    }
  }
}

@main
struct IslandWidgets: WidgetBundle {
  var body: some Widget {
    IslandLiveActivity()
  }
}
