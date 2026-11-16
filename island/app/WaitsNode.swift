import Foundation
import SacredError
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
//
// 「[Opus 5.5] Every failure here is a SacredError made by Island (island/shared/Island.swift),」
// 「[Opus 5.5] which is what sends it: thrown up, or shown where it happened, never dropped.」

// Where the page holds its session (QNTX-Web ts/client/session.ts, KEY).
private let heldAs = "qntx.session"

// A node and a session the island's tests give it, in place of what a build
// names and a page holds (ci/island-tests, against a node on the runner). A
// build of the app never sets either: what it asks is Info.plist's node, in
// the session its page logged in with.
struct WaitsTestedAgainst {
  let node: URL
  let session: String
}
var waitsTestedAgainst: WaitsTestedAgainst?

// Where the node is: Info.plist's QNTXNode, written when the app is built
// (.github/scripts/ios-project.py), as the page's own API origin is.
private func theNode() throws -> URL {
  if let tested = waitsTestedAgainst { return tested.node }
  let said = Bundle.main.object(forInfoDictionaryKey: "QNTXNode") as? String
  guard let said = said, let node = URL(string: said), node.scheme == "https", node.host != nil else {
    throw Island.failed(
      "this build names no node", "Info.plist's QNTXNode is \(String(describing: said)), and an https URL is asked",
      region: "node")
  }
  return node
}

// A session is kept for the node it is of, by its origin: scheme, host and
// port, as it was kept before. theNode said both scheme and host are there.
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
  let status = SecItemCopyMatching(asks as CFDictionary, &found)
  if status == errSecItemNotFound { return nil }
  guard status == errSecSuccess, let raw = found as? Data else {
    Island.failed("the kept session was not read", "the Keychain answered \(status)", region: "session")
    return nil
  }
  guard let session = String(data: raw, encoding: .utf8) else {
    Island.failed("the kept session is not text", "\(raw.count) bytes the Keychain held are not UTF-8", region: "session")
    return nil
  }
  return session
}

private func keep(_ session: String?, for node: URL) {
  let gone = SecItemDelete(keychain(node) as CFDictionary)
  if gone != errSecSuccess && gone != errSecItemNotFound {
    Island.failed("the kept session was not let go of", "the Keychain answered \(gone)", region: "session")
  }
  guard let session = session, !session.isEmpty else { return }
  var adds = keychain(node)
  adds[kSecValueData as String] = Data(session.utf8)
  // Read with the phone locked too: a press on the lock screen is answered there.
  adds[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
  let added = SecItemAdd(adds as CFDictionary, nil)
  if added != errSecSuccess {
    Island.failed("the session was not kept", "the Keychain answered \(added)", region: "session")
  }
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
  if let tested = waitsTestedAgainst { return (tested.session, "tested") }
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
      if let error = error {
        Island.failed("the page was not asked for its session", from: error, region: "session", severity: .warn)
        answer(nil)
        return
      }
      guard let held = result as? String else {
        Island.failed(
          "the page answered its session with no text", String(describing: result), region: "session", severity: .warn)
        answer(nil)
        return
      }
      answer(held)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
      if once { return }
      Island.failed("the page gave no answer", "asked for its session, it said nothing in 3 seconds", region: "session", severity: .warn)
      answer(nil)
    }
  }
  guard let session = said else {
    let held = kept(for: node)
    return (held, held == nil ? "page-gave-no-answer-none-kept" : "kept")
  }
  if session.isEmpty, let held = kept(for: node) {
    return await restored(held, to: page, at: node)
  }
  keep(session, for: node)
  return (session.isEmpty ? nil : session, session.isEmpty ? "page-holds-none" : "page")
}

// The page holds no session and the Keychain holds one. The page's storage
// does not outlive the app's process: q admitted the app as ROOT at 19:13:04
// on 2026-11-14, the app started again at 19:14:00, and at 19:14:16 its page
// held none. What the node still admits is put back into the page, which is
// loaded again with it. What the node ended, by a logout or otherwise, is
// let go of. Where the node is not reached, what is kept stays kept.
@MainActor
private func restored(_ held: String, to page: WKWebView, at node: URL) async -> (session: String?, from: String) {
  guard let at = URL(string: "/auth/user/arrival", relativeTo: node) else {
    Island.failed("the node's arrival is no URL", "/auth/user/arrival under \(node)", region: "session")
    return (held, "kept")
  }
  var asks = URLRequest(url: at)
  asks.timeoutInterval = 10
  asks.httpShouldHandleCookies = false
  asks.setValue("Bearer \(held)", forHTTPHeaderField: "Authorization")
  let answer: URLResponse
  do {
    (_, answer) = try await URLSession.shared.data(for: asks)
  } catch {
    Island.failed("the kept session was not asked of the node", from: error, region: "session", severity: .warn)
    return (held, "kept-node-not-reached")
  }
  guard let status = (answer as? HTTPURLResponse)?.statusCode else {
    Island.failed("the node's answer is no HTTP", String(describing: answer), region: "session")
    return (held, "kept-node-not-reached")
  }
  if status == 401 {
    keep(nil, for: node)
    return (nil, "page-holds-none-node-ended-kept")
  }
  guard (200..<300).contains(status) else {
    Island.failed("the node did not say whether the kept session stands", "it answered \(status)", region: "session")
    return (held, "kept-node-answered-\(status)")
  }
  let both: String
  do {
    both = String(decoding: try JSONSerialization.data(withJSONObject: [heldAs, held]), as: UTF8.self)
  } catch {
    Island.failed("the session was not written for the page", from: error, region: "session")
    return (held, "kept")
  }
  do {
    try await page.evaluateJavaScript("(function(s){localStorage.setItem(s[0], s[1]); location.reload();})(\(both))")
  } catch {
    Island.failed("the session was not put back into the page", from: error, region: "session")
    return (held, "kept")
  }
  waitsIsSeen("restored the session to the page")
  return (held, "restored")
}

// A mark of who is in the app now, to tell one session from the next by. It is not the session.
func waitsSessionMark() async -> String {
  let node: URL
  do {
    node = try theNode()
  } catch {
    return ""
  }
  guard let session = await theSession(at: node).session else { return "" }
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
// 「[Opus 5.5] log. It asks a path the node writes down whoever asks, and says itself in」
// 「[Opus 5.5] the place a client names itself. It carries no session.」
func waitsIsSeen(_ what: String) {
  guard let says = seenAs(what) else { return }
  URLSession.shared.dataTask(with: says) { _, _, error in
    if let error = error {
      Island.failed("a step was not said to the node", from: error, region: "seen", severity: .warn)
    }
  }.resume()
}

// The same, said before it returns. A press runs in a process the system
// suspends as soon as the press returns, and what was only begun then never
// 「[Opus 5.5] leaves the phone: a press says each step this way.」
func waitsIsHeard(_ what: String) async {
  guard let says = seenAs(what) else { return }
  do {
    let (_, answer) = try await URLSession.shared.data(for: says)
    if !(answer is HTTPURLResponse) {
      Island.failed("a step said to the node had no HTTP answer", String(describing: answer), region: "seen", severity: .warn)
    }
  } catch {
    Island.failed("a step was not said to the node", from: error, region: "seen", severity: .warn)
  }
}

private func seenAs(_ what: String) -> URLRequest? {
  let node: URL
  do {
    node = try theNode()
  } catch {
    return nil
  }
  guard let at = URL(string: "/api/phones", relativeTo: node) else {
    Island.failed("the node's phones are no URL", "/api/phones under \(node)", region: "seen")
    return nil
  }
  let plain = String(what.unicodeScalars.filter { $0.isASCII && $0.value >= 32 }.prefix(160))
  var says = URLRequest(url: at)
  says.httpMethod = "GET"
  says.timeoutInterval = 10
  says.httpShouldHandleCookies = false
  says.setValue("QNTX-waits/\(Island.build) \(plain)", forHTTPHeaderField: "User-Agent")
  return says
}

// Asks the node at path, a path of its API, with what is sent there. Throws
// 「[Opus 5.5] the SacredError of what the node answered when it did not do it.」
func waitsNodeIsAsked(_ path: String, _ sent: [String: Any]) async throws {
  // A path of the node's API and nothing else: what is asked never leaves the node.
  guard path.hasPrefix("/api/"), !path.contains(".."), !path.contains("//"), !path.contains("@") else {
    throw Island.failed("a press asked outside the node", "\(path) is no path of the node's", region: "node")
  }
  let node = try theNode()
  guard let at = URL(string: path, relativeTo: node), at.host == node.host else {
    throw Island.failed("a press asked outside the node", "\(path) is no path of the node's", region: "node")
  }
  let (session, from) = await theSession(at: node)
  let cookies = await theCookies(for: at)
  guard session != nil || !cookies.isEmpty else {
    waitsIsSeen("not-logged-in session=\(from) cookies=0 asked=\(path)")
    throw Island.failed(
      "the app is not logged in", "asked \(path) with no session (\(from)) and no cookie", region: "session",
      severity: .warn)
  }
  var asks = URLRequest(url: at)
  asks.httpMethod = "POST"
  asks.timeoutInterval = 20
  asks.httpShouldHandleCookies = false
  asks.setValue("application/json", forHTTPHeaderField: "Content-Type")
  asks.setValue("QNTX-waits/\(Island.build) session=\(from) cookies=\(cookies.count)", forHTTPHeaderField: "User-Agent")
  if let session = session {
    asks.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
  }
  for (name, value) in HTTPCookie.requestHeaderFields(with: cookies) {
    asks.setValue(value, forHTTPHeaderField: name)
  }
  do {
    asks.httpBody = try JSONSerialization.data(withJSONObject: sent)
  } catch {
    throw Island.failed("what a press sends is not JSON", from: error, region: "node")
  }
  let said: Data
  let answer: URLResponse
  do {
    (said, answer) = try await URLSession.shared.data(for: asks)
  } catch {
    throw Island.failed("the node was not reached", from: error, region: "node")
  }
  guard let status = (answer as? HTTPURLResponse)?.statusCode else {
    throw Island.failed("the node's answer is no HTTP", String(describing: answer), region: "node")
  }
  // A session the node no longer admits is not kept: logged out, the node
  // ended it (teranos/QNTX server/auth, handleLogout), and it is never
  // 「[Opus 5.5] presented from here again. Only the session this asking presented: one」
  // 「[Opus 5.5] kept since, by another login, is not the one the node refused.」
  if status == 401 {
    if kept(for: node) == session {
      keep(nil, for: node)
    }
  }
  guard (200..<300).contains(status) else {
    throw Island.failed(
      "the node did not do what was pressed", "\(path) answered \(status)", region: "node",
      raw: String(decoding: said.prefix(2000), as: UTF8.self))
  }
}
