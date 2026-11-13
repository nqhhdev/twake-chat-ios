import Foundation

/// What the sign-in feature needs from the data layer. Implemented in MatrixData; no SDK type appears here (ADR 0006).
/// Every call throws `AuthenticationError`. Sign-in follows the Flutter app: Twake SSO through the registration site
/// or the homeserver's SSO, and a password only on a server without SSO.
public protocol AuthenticationRepository: Sendable {
  /// Discovers a homeserver from what the user typed (a server name or a URL) and reads how it lets users sign in.
  func loginOptions(server: String) async throws(AuthenticationError) -> HomeserverLoginOptions

  /// Signs in with a username and a password and saves the session.
  func login(homeserver: URL, username: String, password: String) async throws(AuthenticationError)
    -> UserSession

  /// Prepares an SSO sign-in on `homeserver` and returns the URL to open in a web authentication session. With an
  /// identity provider, the URL is the homeserver's SSO redirect for it; the registration-site flow passes `nil` and
  /// opens its own URL, then finishes with the callback all the same.
  func startSSOLogin(homeserver: URL, identityProviderId: String?, redirectURL: URL)
    async throws(AuthenticationError) -> URL

  /// Finishes the SSO sign-in started last with the web session's callback URL, which carries the `loginToken`, and
  /// saves the session. A callback without a token throws `invalidCredentials`.
  func finishSSOLogin(callbackURL: URL) async throws(AuthenticationError) -> UserSession

  /// Drops an SSO sign-in that was started and not finished (the user cancelled the web session).
  func cancelSSOLogin() async

  /// The saved session, or `nil` when nobody is signed in.
  func restoreSession() async throws(AuthenticationError) -> UserSession?

  /// Signs out and removes the saved session (ADR 0007).
  func logout() async throws(AuthenticationError)
}
