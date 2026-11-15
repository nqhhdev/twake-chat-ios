import Foundation
import os

/// Logs why an SDK call failed, in Debug builds only, so a failure that the Domain maps to one case (such as
/// `TimelineError.requestFailed`) can be read with `xcrun simctl spawn <udid> log stream --predicate
/// 'subsystem == "org.linagora.twake.chat"'`. Callers pass the SDK error, never message content (ADR 0009).
enum DebugLog {
  #if DEBUG
    private static let logger = Logger(subsystem: "org.linagora.twake.chat", category: "MatrixData")
  #endif

  static func failure(_ operation: String, _ error: any Error) {
    #if DEBUG
      logger.error(
        "\(operation, privacy: .public) failed: \(String(reflecting: error), privacy: .public)")
    #endif
  }
}
