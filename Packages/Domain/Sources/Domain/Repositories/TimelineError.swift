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
  /// The server refused the content as too large (`M_TOO_LARGE`).
  case tooLarge
  /// The file's type cannot be sent: its MIME type is missing or not valid.
  case unsupportedType
  /// The server could not be reached.
  case network
  /// The server refused the request for this user (`M_FORBIDDEN`), such as sending in a read-only chat.
  case forbidden
  /// The attachment could not be read, described or uploaded.
  case uploadFailed
}
