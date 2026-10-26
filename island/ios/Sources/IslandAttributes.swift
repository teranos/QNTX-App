import Foundation

#if canImport(ActivityKit)
import ActivityKit

// What an approval is on the island: the pull request it waits on, and what
// stands now. This file is compiled into the app's plugin and into the island
// widget both, so the two read one shape.
@available(iOS 16.1, *)
struct IslandAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    // What the approval says now: "waits on you", "merging when main CI passes".
    var says: String
    // Each check on its head, as approvals.go writes it down.
    var checks: [IslandCheck]
  }

  // owner/repo#n, as approvalSubject names it.
  var pullRequest: String
  var title: String
}

// One check on the head: its name, and the segment it is drawn as, waiting,
// running, done or failed.
struct IslandCheck: Codable, Hashable {
  var name: String
  var state: String
}
#endif
