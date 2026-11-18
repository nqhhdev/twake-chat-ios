import Foundation

/// How far a chat fills itself when its content is shorter than the viewport, or when no message has shown yet.
///
/// One scroll to the top loads one page; these limits only apply to that short-content fill, so a long room never
/// pages on its own (issue #80).
public struct HistoryLoading: Sendable, Equatable {
  /// Pages loaded in a row to fill a short timeline before it pauses and offers "Load earlier messages".
  public var maxAutomaticPages: Int
  /// Failed pages in a row before it pauses.
  public var maxFailures: Int
  /// The wait between two pages, and after a failed one.
  public var pause: Duration
  public var pauseAfterFailure: Duration

  public init(
    maxAutomaticPages: Int = 3, maxFailures: Int = 3, pause: Duration = .milliseconds(250),
    pauseAfterFailure: Duration = .seconds(3)
  ) {
    self.maxAutomaticPages = maxAutomaticPages
    self.maxFailures = maxFailures
    self.pause = pause
    self.pauseAfterFailure = pauseAfterFailure
  }
}
