import Foundation

/// How far a chat loads older messages by itself while the top of the timeline is on screen.
///
/// The Flutter app asks for history once when fewer than 30 events show (`_tryRequestHistory`); here the timeline
/// keeps asking while its top is visible, so these limits stop a room that has nothing to show from loading forever.
public struct HistoryLoading: Sendable, Equatable {
  /// Pages loaded in a row before the timeline pauses and offers "Load earlier messages".
  public var maxAutomaticPages: Int
  /// Failed pages in a row before it pauses.
  public var maxFailures: Int
  /// The wait between two pages, and after a failed one.
  public var pause: Duration
  public var pauseAfterFailure: Duration

  public init(
    maxAutomaticPages: Int = 10, maxFailures: Int = 3, pause: Duration = .milliseconds(250),
    pauseAfterFailure: Duration = .seconds(3)
  ) {
    self.maxAutomaticPages = maxAutomaticPages
    self.maxFailures = maxFailures
    self.pause = pause
    self.pauseAfterFailure = pauseAfterFailure
  }
}
