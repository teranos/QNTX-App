import Foundation
import Security
import UIKit
import WebKit

// The node, asked from the app's own process as the page asks it: at the
// origin the app was built for, with the session the page is logged in with.
//
// The app's page is at another site than the node, so no cookie of the node's
// rides its requests: the page holds its session itself and presents it as a
// bearer on each one (QNTX-Web ts/client/session.ts), and the node admits
// that as the person (teranos/QNTX server/auth/presented.go). What is asked
// here presents the same session: it is read from the page while the page is
// there, and kept in the Keychain for when the system runs the app with no
// page, as it does for a press on the island. Where the page is let keep the
// node's cookies, those are presented too. No token is made for it.

struct WaitsNodeRefused: LocalizedError {
  let says: String
  var errorDescription: String? { says }
}

// Where the page holds its session (QNTX-Web ts/client/session.ts, KEY).
private let heldAs = "qntx.session"

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

// A session is kept for the node it is of, by its whole origin: scheme, host
// and port. One kept for another node at the same host is not this node's.
private func keychain(_ node: URL) -> [String: Any] {
  var origin = (node.scheme ?? "") + "://" + (node.host ?? "")
  if let port = node.port { origin += ":" + String(port) }
  return [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: heldAs,
    kSecAttrAccount as String: origin,
  ]
}

private func kept(for node: URL) -> String? {
  var asks = keychain(node)
  asks[kSecReturnData as String] = true
  asks[kSecMatchLimit as String] = kSecMatchLimitOne
  var found: CFTypeRef?
  guard SecItemCopyMatching(asks as CFDictionary, &found) == errSecSuccess, let raw = found as? Data else {
    return nil
  }
  return String(data: raw, encoding: .utf8)
}

private func keep(_ session: String?, for node: URL) {
  SecItemDelete(keychain(node) as CFDictionary)
  guard let session = session, !session.isEmpty else { return }
  var adds = keychain(node)
  adds[kSecValueData as String] = Data(session.utf8)
  // Read with the phone locked too: a press on the lock screen is answered there.
  adds[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
  SecItemAdd(adds as CFDictionary, nil)
}

// The app's page, where there is one: the web view Tauri put in the window.
@MainActor
private func thePage() -> WKWebView? {
  func within(_ view: UIView) -> WKWebView? {
    if let page = view as? WKWebView { return page }
    for inner in view.subviews {
      if let page = within(inner) { return page }
    }
    return nil
  }
  for scene in UIApplication.shared.connectedScenes {
    guard let windows = (scene as? UIWindowScene)?.windows else { continue }
    for window in windows {
      if let page = within(window) { return page }
    }
  }
  return nil
}

// The session the app is in, and where it was found. Asked of the page while
// it is there, and what the page says is what stands: logged out, nothing is
// kept. With no page, what was kept when there last was one.
@MainActor
private func theSession(at node: URL) async -> (session: String?, from: String) {
  guard let page = thePage() else {
    let held = kept(for: node)
    return (held, held == nil ? "no-page-none-kept" : "kept")
  }
  guard page.url != nil, !page.isLoading else {
    let held = kept(for: node)
    return (held, held == nil ? "page-loading-none-kept" : "kept")
  }
  // A page the system has suspended may never answer: it is given three
  // seconds, and then what was kept stands. A press is not left waiting on it.
  let said: String? = await withCheckedContinuation { (answered: CheckedContinuation<String?, Never>) in
    var once = false
    let answer: (String?) -> Void = { said in
      if once { return }
      once = true
      answered.resume(returning: said)
    }
    page.evaluateJavaScript("localStorage.getItem('\(heldAs)') || ''") { result, error in
      answer(error == nil ? (result as? String ?? "") : nil)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { answer(nil) }
  }
  guard let session = said else {
    let held = kept(for: node)
    return (held, held == nil ? "page-gave-no-answer-none-kept" : "kept")
  }
  keep(session, for: node)
  return (session.isEmpty ? nil : session, session.isEmpty ? "page-holds-none" : "page")
}

// A mark of who is in the app now, to tell one session from the next by. It is not the session.
func waitsSessionMark() async -> String {
  guard let node = try? theNode(), let session = await theSession(at: node).session else { return "" }
  var mark: UInt64 = 1469598103934665603
  for byte in session.utf8 {
    mark = (mark ^ UInt64(byte)) &* 1099511628211
  }
  return String(mark, radix: 16)
}

// The node's own cookies in the page's store, as a browser would send them to
// what is asked: where the page is let keep them, the session rides there, as
// it does on the node's own web. A cookie set for one host alone goes to that
// host alone, one set for a domain to the hosts under it, and each only where
// its path leads and, kept for https, only over https.
@MainActor
private func theCookies(for asked: URL) async -> [HTTPCookie] {
  let all = await withCheckedContinuation { (found: CheckedContinuation<[HTTPCookie], Never>) in
    WKWebsiteDataStore.default().httpCookieStore.getAllCookies { found.resume(returning: $0) }
  }
  guard let host = asked.host else { return [] }
  let path = asked.path.isEmpty ? "/" : asked.path
  return all.filter { cookie in
    let ofThisHost: Bool
    if cookie.domain.hasPrefix(".") {
      let domain = String(cookie.domain.dropFirst())
      ofThisHost = host == domain || host.hasSuffix("." + domain)
    } else {
      ofThisHost = host == cookie.domain
    }
    let under = cookie.path.hasSuffix("/") ? cookie.path : cookie.path + "/"
    let onThisPath = cookie.path == "/" || path == cookie.path || path.hasPrefix(under)
    return ofThisHost && onThisPath && (!cookie.isSecure || asked.scheme == "https")
  }
}

// What this side is doing, said to the node so that it stands in the node's
// log: nothing on a phone is seen from anywhere else. It asks a path the node
// writes down whoever asks, and says itself in the place a client names
// itself. It carries no session and is answered by nothing that matters.
func waitsIsSeen(_ what: String) {
  guard let node = try? theNode(), let at = URL(string: "/api/phones", relativeTo: node) else { return }
  let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
  let plain = String(what.unicodeScalars.filter { $0.isASCII && $0.value >= 32 }.prefix(160))
  var says = URLRequest(url: at)
  says.httpMethod = "GET"
  says.timeoutInterval = 10
  says.httpShouldHandleCookies = false
  says.setValue("QNTX-waits/\(build) \(plain)", forHTTPHeaderField: "User-Agent")
  URLSession.shared.dataTask(with: says).resume()
}

// Asks the node at path, a path of its API, with what is sent there. Throws
// what the node answered when it did not do it.
func waitsNodeIsAsked(_ path: String, _ sent: [String: Any]) async throws {
  // A path of the node's API and nothing else: what is asked never leaves the node.
  guard path.hasPrefix("/api/"), !path.contains(".."), !path.contains("//"), !path.contains("@") else {
    throw WaitsNodeRefused(says: "\(path) is no path of the node's")
  }
  let node = try theNode()
  guard let at = URL(string: path, relativeTo: node), at.host == node.host else {
    throw WaitsNodeRefused(says: "\(path) is no path of the node's")
  }
  let (session, from) = await theSession(at: node)
  let cookies = await theCookies(for: at)
  guard session != nil || !cookies.isEmpty else {
    waitsIsSeen("not-logged-in session=\(from) cookies=0 asked=\(path)")
    throw WaitsNodeRefused(says: "the app is not logged in")
  }
  var asks = URLRequest(url: at)
  asks.httpMethod = "POST"
  asks.timeoutInterval = 20
  asks.httpShouldHandleCookies = false
  asks.setValue("application/json", forHTTPHeaderField: "Content-Type")
  let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
  asks.setValue("QNTX-waits/\(build) session=\(from) cookies=\(cookies.count)", forHTTPHeaderField: "User-Agent")
  if let session = session {
    asks.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
  }
  for (name, value) in HTTPCookie.requestHeaderFields(with: cookies) {
    asks.setValue(value, forHTTPHeaderField: name)
  }
  asks.httpBody = try JSONSerialization.data(withJSONObject: sent)
  let (said, answer) = try await URLSession.shared.data(for: asks)
  guard let status = (answer as? HTTPURLResponse)?.statusCode else {
    throw WaitsNodeRefused(says: "the node gave no answer")
  }
  // A session the node no longer admits is not kept: logged out, the node
  // ended it (teranos/QNTX server/auth, handleLogout), and it is never
  // presented from here again.
  // Only the session this asking presented: one kept since, by another login,
  // is not the one the node refused.
  if status == 401 {
    if kept(for: node) == session {
      keep(nil, for: node)
    }
  }
  guard (200..<300).contains(status) else {
    let words = String(data: said.prefix(200), encoding: .utf8) ?? ""
    throw WaitsNodeRefused(says: "the node answered \(status) \(words)")
  }
}
