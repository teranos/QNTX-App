import ActivityKit
import Foundation

// "THE BATCH IS A LIVE ACTIVITY"
// "AND SO IS THE APPROCAL"
// "ITS KIND OF THE SAME THING"
//
// What waits on a person, as a Live Activity: one shape for a batch of what
// agents said to an agent, an approval, and whatever waits on a person next.
// The node starts it through Apple and says everything it shows, its presses
// among it (teranos/QNTX server/phones.go, waitsOf and waitsShown): what the
// node sends is decoded into this type by the system, so the two are one
// shape, key for key. This file is compiled into the app and into the island
// widget both.
@available(iOS 17.2, *)
struct WaitsAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    // What it says now: how many wait, or what became of it.
    var says: String
    // What it is about to do, in a few lines.
    var preview: String
    // When it runs out, in seconds since 1970. Zero is over, and nothing counts down.
    var due: Double
    // Its parts and the state each is drawn in: an approval's checks.
    var segments: [WaitsSegment]
    // The answers the person gives on it, in the order they are drawn.
    var presses: [WaitsPress]
  }

  // What it is on the node: collected/ and an agent's DID after it.
  var waits: String
  // What sort of thing waits, which its mark is drawn by.
  var kind: String
  var title: String
}

// One part of what waits: its name, and the segment it is drawn as, waiting,
// running, done or failed.
struct WaitsSegment: Codable, Hashable {
  var name: String
  var state: String
}

// One answer: what the press says, what it says once the node did it, and
// what it asks of the node, at a path of the node's with what is sent there.
struct WaitsPress: Codable, Hashable {
  var says: String
  // What the press is, as the node names it, one of three: approve, delay,
  // cancel. The mark it is drawn as is markOf's, one for each.
  var does: String
  var then: String
  var path: String
  var sent: [String: String]
  // Drawn red: it cannot be undone.
  var armed: Bool
}

// "CANCEL SHOULD BE ONE THING"
// "APPROVE SHOULD BE ONE THING"
// "THEY ARE ESSENTIALLY THE SAME GODDAMN THING"
//
// The mark each press is drawn as, among the system's own (SF Symbols): the
// one place a press is given its mark. A press is one of three. Approve is
// the yes, whatever it is the yes to: sending what waits, merging what was
// asked. Cancel is the no. A press the node names and this does not know is
// drawn as not known, and is seen to be.
func markOf(_ does: String) -> String {
  switch does {
  case "approve": return "checkmark"
  case "delay": return "clock.arrow.circlepath"
  case "cancel": return "nosign"
  default: return "questionmark.square.dashed"
  }
}
