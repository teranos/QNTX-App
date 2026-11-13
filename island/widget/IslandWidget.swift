import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// "the magic island"
// "TO STAY THERE FOR 15 MINYTES, LIKE LUMA DOES"
//
// What waits on a person, drawn: the compact pill with the time left, the
// view held open with what it is and its presses, and the lock screen. The
// Mac's menu bar shows the same. Everything drawn is what the node said
// (island/shared/WaitsAttributes.swift); a press is PressWaits
// (island/shared/WaitsPress.swift).
//
// QNTX's own look: near-black surfaces, the botanical green, JetBrains Mono's
// stand-in (the system monospace), SEG glyphs and no emoji.

private let accent = Color(red: 0x7d / 255, green: 0xba / 255, blue: 0x8a / 255)
private let onDark = Color(red: 0xdf / 255, green: 0xe1 / 255, blue: 0xe0 / 255)
private let onDarkSecondary = Color(red: 0xa9 / 255, green: 0xab / 255, blue: 0xaa / 255)
private let onDarkTertiary = Color(red: 0x86 / 255, green: 0x87 / 255, blue: 0x87 / 255)
private let surface = Color(red: 0x1a / 255, green: 0x1b / 255, blue: 0x1a / 255)
private let raised = Color(red: 0x2a / 255, green: 0x2c / 255, blue: 0x2b / 255)
private let armedRed = Color(red: 0xe4 / 255, green: 0x47 / 255, blue: 0x47 / 255)

private let mono = Font.system(size: 11, design: .monospaced)

// The segment a part is drawn as.
private func colorOf(_ state: String) -> Color {
  switch state {
  case "done": return Color(red: 0x22 / 255, green: 0xc6 / 255, blue: 0x5e / 255)
  case "failed": return armedRed
  case "running": return Color(red: 0x63 / 255, green: 0x94 / 255, blue: 0xd5 / 255)
  default: return Color(red: 0x3f / 255, green: 0x41 / 255, blue: 0x40 / 255)
  }
}

private struct Segments: View {
  let segments: [WaitsSegment]
  let height: CGFloat

  var body: some View {
    HStack(spacing: 3) {
      ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
        RoundedRectangle(cornerRadius: 1)
          .fill(colorOf(segment.state))
          .frame(height: height)
      }
    }
    .accessibilityElement()
    .accessibilityLabel(segments.map { "\($0.name) \($0.state)" }.joined(separator: ", "))
  }
}

// The time left until it runs out, counting down by itself: the system draws
// it, and nothing has to say each second to it.
@available(iOS 17.2, *)
private struct TimeLeft: View {
  let due: Double
  let size: CGFloat

  var body: some View {
    let until = Date(timeIntervalSince1970: due)
    if due > 0, until > Date() {
      Text(timerInterval: Date()...until, countsDown: true, showsHours: false)
        .font(.system(size: size, weight: .semibold, design: .monospaced))
        .monospacedDigit()
        .foregroundColor(accent)
        .multilineTextAlignment(.trailing)
    }
  }
}

// The person's answers, each one a press that asks the node without the app being opened.
@available(iOS 17.2, *)
private struct Presses: View {
  let activity: String
  let presses: [WaitsPress]

  var body: some View {
    HStack(spacing: 8) {
      ForEach(Array(presses.enumerated()), id: \.offset) { at, press in
        Button(intent: PressWaits(activity: activity, press: at, asks: press.asks)) {
          // "I FIND THAT CANCER EVERYWEHERE WHERE YOU DO THIS"
          // A press is the system's own mark and no word: the word is what is read out for it.
          Image(systemName: markOf(press.does))
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(press.armed ? armedRed : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(raised)
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(press.says)
      }
    }
  }
}

@available(iOS 17.2, *)
struct WaitsLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: WaitsAttributes.self) { context in
      // The lock screen.
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text("꩜ qntx · \(context.attributes.kind)").font(mono).foregroundColor(onDarkTertiary)
          Spacer()
          TimeLeft(due: context.state.due, size: 13)
        }
        VStack(alignment: .leading, spacing: 3) {
          Text("\(context.state.says) \(context.attributes.title)")
            .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
          if !context.state.preview.isEmpty {
            Text(context.state.preview).font(.system(size: 13)).foregroundColor(onDarkSecondary).lineLimit(4)
          }
        }
        if !context.state.segments.isEmpty {
          Segments(segments: context.state.segments, height: 5)
        }
        if !context.state.presses.isEmpty {
          Presses(activity: context.activityID, presses: context.state.presses)
        }
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
          TimeLeft(due: context.state.due, size: 15)
        }
        DynamicIslandExpandedRegion(.center) {
          Text("\(context.state.says) \(context.attributes.title)")
            .font(.system(size: 15, weight: .semibold)).foregroundColor(.white).lineLimit(1)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 8) {
            if !context.state.preview.isEmpty {
              Text(context.state.preview).font(.system(size: 13)).foregroundColor(onDarkSecondary).lineLimit(3)
            }
            if !context.state.segments.isEmpty {
              Segments(segments: context.state.segments, height: 4)
            }
            if !context.state.presses.isEmpty {
              Presses(activity: context.activityID, presses: context.state.presses)
            }
          }
        }
      } compactLeading: {
        Text("꩜").font(.system(size: 14, design: .monospaced)).foregroundColor(accent)
      } compactTrailing: {
        TimeLeft(due: context.state.due, size: 13).frame(maxWidth: 52)
      } minimal: {
        Text("꩜").font(.system(size: 13, design: .monospaced)).foregroundColor(accent)
      }
    }
  }
}

@main
struct IslandWidgets: WidgetBundle {
  var body: some Widget {
    if #available(iOS 17.2, *) {
      WaitsLiveActivity()
    }
  }
}
