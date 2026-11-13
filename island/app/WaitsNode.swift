import Foundation
import WebKit

// The node, asked from the app's own process as the page asks it: at the
// origin the app was built for, with the session the page is logged in with.
// The session is a cookie the page's web view holds, and it is read from
// where the web view keeps it.

struct WaitsNodeRefused: LocalizedError {
  let says: String
  var errorDescription: String? { says }
}

// Where the node is: Info.plist's QNTXNode, written when the app is built
// (.github/scripts/ios-project.py), as the page's own API origin is.
private func theNode() throws -> URL {
  guard let said = Bundle.main.object(forInfoDictionaryKey: "QNTXNode") as? String, let node = URL(string: said),
    node.scheme == "https", node.host != nil
  else {
    throw WaitsNodeRefused(says: "this build names no node")
  }
  return node
}

@MainActor
private func theSession(at node: URL) async -> [HTTPCookie] {
  let all = await withCheckedContinuation { (found: CheckedContinuation<[HTTPCookie], Never>) in
    WKWebsiteDataStore.default().httpCookieStore.getAllCookies { found.resume(returning: $0) }
  }
  guard let host = node.host else { return [] }
  // A cookie of the node's host, or of a domain the host is under.
  return all.filter { cookie in
    let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
    return host == domain || host.hasSuffix("." + domain)
  }
}

// Asks the node at path, a path of its API, with what is sent there. Throws
// what the node answered when it did not do it.
func waitsNodeIsAsked(_ path: String, _ sent: [String: String]) async throws {
  // A path of the node's API and nothing else: what is asked never leaves the node.
  guard path.hasPrefix("/api/"), !path.contains(".."), !path.contains("//"), !path.contains("@") else {
    throw WaitsNodeRefused(says: "\(path) is no path of the node's")
  }
  let node = try theNode()
  guard let at = URL(string: path, relativeTo: node), at.host == node.host else {
    throw WaitsNodeRefused(says: "\(path) is no path of the node's")
  }
  let session = await theSession(at: node)
  guard !session.isEmpty else {
    throw WaitsNodeRefused(says: "the app is not logged in")
  }
  var asks = URLRequest(url: at)
  asks.httpMethod = "POST"
  asks.timeoutInterval = 20
  asks.httpShouldHandleCookies = false
  asks.setValue("application/json", forHTTPHeaderField: "Content-Type")
  for (name, value) in HTTPCookie.requestHeaderFields(with: session) {
    asks.setValue(value, forHTTPHeaderField: name)
  }
  asks.httpBody = try JSONSerialization.data(withJSONObject: sent)
  let (said, answer) = try await URLSession.shared.data(for: asks)
  guard let status = (answer as? HTTPURLResponse)?.statusCode else {
    throw WaitsNodeRefused(says: "the node gave no answer")
  }
  guard (200..<300).contains(status) else {
    let words = String(data: said.prefix(200), encoding: .utf8) ?? ""
    throw WaitsNodeRefused(says: "the node answered \(status) \(words)")
  }
}
