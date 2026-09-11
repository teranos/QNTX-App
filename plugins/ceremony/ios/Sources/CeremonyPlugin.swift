import AuthenticationServices
import SwiftRs
import Tauri
import UIKit

struct RunArgs: Decodable {
  let url: String
  let scheme: String
}

// The sheet iOS gives a web sign-in. It shares Safari's cookies and passkeys,
// and hands back the URL the node redirects it to, so the ticket arrives here
// and not through a deep link into a relaunched app.
class CeremonyPlugin: Plugin {
  // Held until the sheet calls back. A session nobody holds is released
  // before it opens, and then never calls back.
  private var session: ASWebAuthenticationSession?
  private let anchor = Anchor()

  @objc public func run(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(RunArgs.self)
    guard let url = URL(string: args.url) else {
      invoke.reject("not a url: \(args.url)")
      return
    }
    DispatchQueue.main.async {
      let session = ASWebAuthenticationSession(url: url, callbackURLScheme: args.scheme) {
        cameBack, error in
        self.session = nil
        if let cameBack = cameBack {
          invoke.resolve(["url": cameBack.absoluteString])
          return
        }
        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
          invoke.reject("cancelled")
          return
        }
        invoke.reject(error?.localizedDescription ?? "the sheet closed with no callback")
      }
      session.presentationContextProvider = self.anchor
      // Safari's session is the point: the person's accounts are already there.
      session.prefersEphemeralWebBrowserSession = false
      self.session = session
      if !session.start() {
        self.session = nil
        invoke.reject("the sheet did not open")
      }
    }
  }
}

// Where the sheet is presented: the window the App is showing.
class Anchor: NSObject, ASWebAuthenticationPresentationContextProviding {
  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    return windows.first { $0.isKeyWindow } ?? windows.first ?? ASPresentationAnchor()
  }
}

@_cdecl("init_plugin_ceremony")
func initPlugin() -> Plugin {
  return CeremonyPlugin()
}
