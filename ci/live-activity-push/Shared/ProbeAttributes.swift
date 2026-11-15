import ActivityKit
struct ProbeAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable { var says: String }
  var name: String
}
