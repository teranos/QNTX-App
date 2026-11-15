import Foundation
import SacredError
import Sentry

// "the island is too critical. we need observability into the thing"
//
// 「[Opus 5.5] Every failure of the island is one SacredError (teranos/sacred-error), and」
// 「[Opus 5.5] each is made here, which is the one place it is sent from: to Sentry's」
// 「[Opus 5.5] qntx-island project, where it is kept and raised. The caller holds the same」
// 「[Opus 5.5] value and shows it where it happened. Nothing of the island prints a failure」
// 「[Opus 5.5] and carries on, and nothing turns one into words on its way across.」
enum Island {
  // 「[Opus 5.5] Where failures are sent: Info.plist's QNTXIslandSentry, the DSN of Sentry's」
  // 「[Opus 5.5] qntx-island project, written when the app is built (.github/scripts/ios-project.py)」
  // 「[Opus 5.5] from the repository's ISLAND_SENTRY_DSN variable.」
  private static var dsn: String? {
    Bundle.main.object(forInfoDictionaryKey: "QNTXIslandSentry") as? String
  }

  private static let turn = NSLock()
  private static var made = 0
  // Touched on the main thread only.
  private static var started = false

  // Sentry is begun on the main thread as each process starts, before anything
  // can fail there: the app's at launch (WaitsTokens.begin), the widget's when
  // its bundle is made (IslandWidgets). Sentry begun on another thread starts
  // later, on the main thread, and what is sent before then is lost.
  static func start() {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { start() }
      return
    }
    if started { return }
    started = true
    // A build that names no DSN is refused when it is made (ios-project.py),
    // so one that runs names one.
    SentrySDK.start { options in
      options.dsn = dsn
      options.releaseName = "qntx-island@" + build
    }
  }

  /// 「[Opus 5.5] The build this is, as the bundle names it.」
  static var build: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "a build that names no version"
  }

  /// 「[Opus 5.5] A failure of the island, made and sent: what is returned is what was」
  /// 「[Opus 5.5] sent, and is what the caller throws or shows. Where the caller has」
  /// 「[Opus 5.5] nowhere to show it, it was sent all the same, so it may be let go of.」
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

  /// 「[Opus 5.5] What another layer threw, as the island's: a SacredError stays the one」
  /// 「[Opus 5.5] it is, and was sent when it was made; anything else is made one here,」
  /// 「[Opus 5.5] with what it said and what it is.」
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
    let event = Event(level: level(error.severity))
    event.message = SentryMessage(formatted: error.title)
    event.tags = ["surface": error.context.surface, "region": error.context.region ?? "", "build": build]
    // 「[Opus 5.5] One issue for one failure, whatever its words said this time.」
    event.fingerprint = [error.context.region ?? "", error.title]
    var whole: [String: Any] = [
      "id": error.id, "why": error.why, "at": error.at, "location": error.location ?? "", "raw": error.raw ?? "",
    ]
    whole["trace"] = error.trace
    event.context = ["sacred_error": whole]
    // Sent once Sentry is begun: where it is not yet, on the main thread,
    // after it is.
    if SentrySDK.isEnabled {
      SentrySDK.capture(event: event)
    } else {
      DispatchQueue.main.async {
        start()
        SentrySDK.capture(event: event)
      }
    }
  }

  /// 「[Opus 5.5] Sends what is waiting before the process is let go of: a press runs in a」
  /// 「[Opus 5.5] process the system suspends as soon as the press returns.」
  // "deal with the silence overpowering the loud"
  //
  // A step the island takes, kept with Sentry as a breadcrumb: a failure sent
  // after it carries the steps that led to it, and a step that never ended is
  // the last one named.
  static func step(_ what: String, region: String) {
    let crumb = Breadcrumb(level: .info, category: "island." + region)
    crumb.message = what
    SentrySDK.addBreadcrumb(crumb)
  }

  static func flush() {
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
