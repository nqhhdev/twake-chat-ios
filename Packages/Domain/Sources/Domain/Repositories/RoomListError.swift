import Foundation

/// The expected failures of starting the room list. No case carries text from the server or the SDK.
public enum RoomListError: Error, Sendable, Equatable {
  /// Nobody is signed in, so there is no client to sync.
  case notSignedIn
  /// Sync or the room list service could not be started.
  case syncUnavailable
  /// Joining or leaving the room failed.
  case requestFailed
}
