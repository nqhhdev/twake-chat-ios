import Foundation

/// The expected failures of signing in, restoring a session and signing out.
/// No case carries a token or text from the server.
public enum AuthenticationError: Error, Sendable, Equatable {
  /// The homeserver rejected the username or the password.
  case invalidCredentials
  /// The homeserver could not be reached.
  case serverUnreachable
  /// The homeserver address is not a usable URL, or no Matrix server answers there.
  case invalidHomeserverURL
  /// Any other failure.
  case unknown
}
