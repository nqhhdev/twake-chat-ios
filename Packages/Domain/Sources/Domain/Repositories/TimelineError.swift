import Foundation

/// The expected failures of a room's timeline. No case carries text from the server or the SDK.
public enum TimelineError: Error, Sendable, Equatable {
  /// Nobody is signed in, so there is no client.
  case notSignedIn
  /// The room is not known to the client.
  case roomNotFound
  /// The timeline could not be opened.
  case unavailable
  /// The request failed; trying again may work.
  case requestFailed
}
