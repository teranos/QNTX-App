import ActivityKit
import Foundation

// "THE BATCH IS A LIVE ACTIVITY"
// "AND SO IS THE APPROCAL"
// "ITS KIND OF THE SAME THING"
//
// 「[Fable 5.2, Opus 5.5] What waits on a person, as a Live Activity: one shape for a batch of what」
// 「[Fable 5.2, Opus 5.5] agents said to an agent, an approval, and whatever waits on a person next.」
// 「[Fable 5.2, Opus 5.5] The node starts it through Apple and says everything it shows, its presses」
// 「[Fable 5.2, Opus 5.5] among it (teranos/QNTX server/phones.go, waitsOf and waitsShown): what the」
// 「[Fable 5.2, Opus 5.5] node sends is decoded into this type by the system, so the two are one」
// 「[Fable 5.2, Opus 5.5] shape, key for key. This file is compiled into the app and into the island」
// 「[Fable 5.2, Opus 5.5] widget both.」
@available(iOS 17.2, *)
struct WaitsAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    // 「[Fable 5.2, Opus 5.5] What it says now: how many wait, or what became of it.」
    var says: String
    // 「[Fable 5.2, Opus 5.5] What it is about to do, in a few lines.」
    var preview: String
    // 「[Fable 5.2, Opus 5.5] When it runs out, in seconds since 1970. Zero is over, and nothing counts down.」
    var due: Double
    // 「[Fable 5.2, Opus 5.5] Its parts and the state each is drawn in: an approval's checks.」
    var segments: [WaitsSegment]
    // 「[Fable 5.2, Opus 5.5] The answers the person gives on it, in the order they are drawn.」
    var presses: [WaitsPress]
  }

  // 「[Fable 5.2, Opus 5.5] What it is on the node: collected/ and an agent's DID after it.」
  var waits: String
  // 「[Fable 5.2, Opus 5.5] What sort of thing waits, which its mark is drawn by.」
  var kind: String
  var title: String
}

// 「[Fable 5.2, Opus 5.5] One part of what waits: its name, and the segment it is drawn as, waiting,」
// 「[Fable 5.2, Opus 5.5] running, done or failed.」
struct WaitsSegment: Codable, Hashable {
  var name: String
  var state: String
}

// 「[Fable 5.2, Opus 5.5] One answer: what the press says, what it says once the node did it, and」
// 「[Fable 5.2, Opus 5.5] what it asks of the node, at a path of the node's with what is sent there.」
struct WaitsPress: Codable, Hashable {
  var says: String
  // 「[Fable 5.2, Opus 5.5] What the press is, as the node names it, one of three: approve, delay,」
  // 「[Fable 5.2, Opus 5.5] cancel. The mark it is drawn as is markOf's, one for each.」
  var does: String
  var then: String
  var path: String
  var sent: [String: String]
  // 「[Fable 5.2, Opus 5.5] Drawn red: it cannot be undone.」
  var armed: Bool
}

// "CANCEL SHOULD BE ONE THING"
// "APPROVE SHOULD BE ONE THING"
// "THEY ARE ESSENTIALLY THE SAME GODDAMN THING"
//
// 「[Fable 5.2, Opus 5.5] The mark each press is drawn as, among the system's own (SF Symbols): the」
// 「[Fable 5.2, Opus 5.5] one place a press is given its mark. A press is one of three. Approve is」
// 「[Fable 5.2, Opus 5.5] the yes, whatever it is the yes to: sending what waits, merging what was」
// 「[Fable 5.2, Opus 5.5] asked. Cancel is the no. A press the node names and this does not know is」
// 「[Fable 5.2, Opus 5.5] drawn as not known, and is seen to be.」
func markOf(_ does: String) -> String {
  switch does {
  case "approve": return "checkmark"
  case "delay": return "clock.arrow.circlepath"
  case "cancel": return "nosign"
  default: return "questionmark.square.dashed"
  }
}
