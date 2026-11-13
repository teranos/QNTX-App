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
// page, as it does for a press on the island. No token is made for it.

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
    node.scheme == "https" || node.scheme == "http", node.host != nil
  else {
    throw WaitsNodeRefused(says: "this build names no node")
  }
  return node
}

private func keychain(_ node: URL) -> [String: Any] {
  [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: heldAs,
    kSecAttrAccount as String: node.host ?? "",
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

// The session the app is in. Asked of the page while it is there, and what
// the page says is what stands: logged out, nothing is kept. With no page,
// what was kept when there last was one.
@MainActor
private func theSession(at node: URL) async -> String? {
  guard let page = thePage(), page.url != nil, !page.isLoading else {
    return kept(for: node)
  }
  do {
    let said = try await page.evaluateJavaScript("localStorage.getItem('\(heldAs)') || ''")
    let session = said as? String ?? ""
    keep(session, for: node)
    return session.isEmpty ? nil : session
  } catch {
    return kept(for: node)
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
  guard let session = await theSession(at: node) else {
    throw WaitsNodeRefused(says: "the app is not logged in")
  }
  var asks = URLRequest(url: at)
  asks.httpMethod = "POST"
  asks.timeoutInterval = 20
  asks.httpShouldHandleCookies = false
  asks.setValue("application/json", forHTTPHeaderField: "Content-Type")
  asks.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
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
