import Foundation
import SacredError
import Sentry

// "the island is too critical. we need observability into the thing"
//
// Every failure of the island is one SacredError (teranos/sacred-error), and
// each is made here, which is the one place it is sent from: to Sentry's
// qntx-island project, where it is kept and raised. The caller holds the same
// value and shows it where it happened. Nothing of the island prints a failure
// and carries on, and nothing turns one into words on its way across.
enum Island {
  // Where failures are sent: Info.plist's QNTXIslandSentry, the DSN of Sentry's
  // qntx-island project, written when the app is built (.github/scripts/ios-project.py)
  // from the repository's ISLAND_SENTRY_DSN variable.
  private static var dsn: String? {
    Bundle.main.object(forInfoDictionaryKey: "QNTXIslandSentry") as? String
  }

  private static let turn = NSLock()
  private static var started = false
  private static var made = 0

  // Sentry, begun the first time anything is sent: the app and the widget are
  // two processes, and either may be the first to fail.
  private static func start() {
    turn.lock()
    defer { turn.unlock() }
    if started { return }
    started = true
    // A build that names no DSN is refused when it is made (ios-project.py),
    // so one that runs names one.
    SentrySDK.start { options in
      options.dsn = dsn
      options.releaseName = "qntx-island@" + build
    }
  }

  /// The build this is, as the bundle names it.
  static var build: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "a build that names no version"
  }

  /// A failure of the island, made and sent: what is returned is what was
  /// sent, and is what the caller throws or shows. Where the caller has
  /// nowhere to show it, it was sent all the same, so it may be let go of.
  @discardableResult
  static func failed(
    _ title: String, _ why: String, region: String, severity: Severity = .error, raw: String? = nil,
    file: String = #fileID, line: Int = #line
  ) -> SacredError {
    turn.lock()
    made += 1
    let id = "err-island-\(made)"
    turn.unlock()
    let error = SacredError(
      id: id, severity: severity, context: Context(surface: "island", region: region), title: title, why: why,
      raw: raw, at: ISO8601DateFormatter().string(from: Date()), source: "swift", location: "\(file):\(line)")
    send(error)
    return error
  }

  /// What another layer threw, as the island's: a SacredError stays the one
  /// it is, and was sent when it was made; anything else is made one here,
  /// with what it said and what it is.
  @discardableResult
  static func failed(
    _ title: String, from error: Error, region: String, severity: Severity = .error,
    file: String = #fileID, line: Int = #line
  ) -> SacredError {
    if let sacred = error as? SacredError { return sacred }
    return failed(
      title, error.localizedDescription, region: region, severity: severity, raw: String(reflecting: error),
      file: file, line: line)
  }

  private static func send(_ error: SacredError) {
    start()
    let event = Event(level: level(error.severity))
    event.message = SentryMessage(formatted: error.title)
    event.tags = ["surface": error.context.surface, "region": error.context.region ?? "", "build": build]
    // One issue for one failure, whatever its words said this time.
    event.fingerprint = [error.context.region ?? "", error.title]
    var whole: [String: Any] = [
      "id": error.id, "why": error.why, "at": error.at, "location": error.location ?? "", "raw": error.raw ?? "",
    ]
    whole["trace"] = error.trace
    event.context = ["sacred_error": whole]
    SentrySDK.capture(event: event)
  }

  /// Sends what is waiting before the process is let go of: a press runs in a
  /// process the system suspends as soon as the press returns.
  static func flush() {
    start()
    SentrySDK.flush(timeout: 2)
  }

  private static func level(_ severity: Severity) -> SentryLevel {
    switch severity {
    case .info: return .info
    case .warn: return .warning
    case .error: return .error
    case .panic: return .fatal
    }
  }
}
