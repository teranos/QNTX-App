import Foundation

#if canImport(ActivityKit)
import ActivityKit

// 「[Opus 5.5, Fable 5.2] What an approval is on the island: the pull request it waits on, and what」
// 「[Opus 5.5, Fable 5.2] stands now. This file is compiled into the app's plugin and into the island」
// 「[Opus 5.5, Fable 5.2] widget both, so the two read one shape.」
@available(iOS 16.1, *)
struct IslandAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    // 「[Opus 5.5, Fable 5.2] What the approval says now: "waits on you", "merging when main CI passes".」
    var says: String
    // 「[Opus 5.5, Fable 5.2] Each check on its head, as approvals.go writes it down.」
    var checks: [IslandCheck]
  }

  // 「[Opus 5.5, Fable 5.2] owner/repo#n, as approvalSubject names it.」
  var pullRequest: String
  var title: String
}

// 「[Opus 5.5, Fable 5.2] One check on the head: its name, and the segment it is drawn as, waiting,」
// 「[Opus 5.5, Fable 5.2] running, done or failed.」
struct IslandCheck: Codable, Hashable {
  var name: String
  var state: String
}
#endif
