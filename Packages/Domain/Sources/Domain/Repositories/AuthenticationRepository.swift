import Foundation

/// What the sign-in feature needs from the data layer. Implemented in MatrixData; no SDK type appears here (ADR 0006).
/// Every call throws `AuthenticationError`.
public protocol AuthenticationRepository: Sendable {
  /// Signs in with a username and a password (Debug builds only, ADR 0019) and saves the session.
  func login(homeserver: URL, username: String, password: String) async throws(AuthenticationError)
    -> UserSession

  /// The saved session, or `nil` when nobody is signed in.
  func restoreSession() async throws(AuthenticationError) -> UserSession?

  /// Signs out and removes the saved session (ADR 0007).
  func logout() async throws(AuthenticationError)
}
