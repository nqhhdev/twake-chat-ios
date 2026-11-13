import Domain
import Foundation

/// The SSO round trip both the Twake ID buttons and the company server use (connect_page_mixin.dart): the repository
/// prepares the sign-in, the web session opens the page, and the callback's `loginToken` finishes it.
struct SSOSignIn: Sendable {
  let repository: any AuthenticationRepository
  let webAuthenticator: any WebAuthenticator

  enum Failure: Error, Equatable {
    case cancelled
    case authentication(AuthenticationError)
  }

  /// Signs in on `homeserver`. `page` replaces the homeserver's SSO page, as the registration site does.
  @MainActor
  func signIn(homeserver: URL, identityProviderId: String?, redirectURL: URL, page: URL? = nil)
    async throws(Failure) -> UserSession
  {
    let ssoURL: URL
    do {
      ssoURL = try await repository.startSSOLogin(
        homeserver: homeserver, identityProviderId: identityProviderId, redirectURL: redirectURL)
    } catch {
      throw .authentication(error)
    }
    let callback: URL
    do {
      callback = try await webAuthenticator.authenticate(
        url: page ?? ssoURL, callbackScheme: SignInConfiguration.callbackScheme)
    } catch {
      await repository.cancelSSOLogin()
      throw error == .cancelled ? .cancelled : .authentication(.unknown)
    }
    do {
      return try await repository.finishSSOLogin(callbackURL: callback)
    } catch {
      throw .authentication(error)
    }
  }
}

/// The Flutter app's messages for a failed sign-in.
enum SignInMessages {
  static func message(for error: AuthenticationError) -> String {
    switch error {
    case .invalidCredentials: "Invalid username or password"
    case .serverUnreachable: "No connection to the server"
    case .invalidHomeserverURL: "Wrong server name"
    case .unknown: "Oops, something went wrong…"
    }
  }
}
