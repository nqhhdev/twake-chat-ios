import Domain
import Foundation
import Observation

/// The first screen when nobody is signed in, as the Flutter app's `TwakeWelcome` (twake_welcome.dart:62-139):
/// Sign in and Create Twake ID open the Twake registration site and sign in to the workplace homeserver with the
/// `loginToken` it returns; "Use your company server" opens the homeserver picker.
@MainActor @Observable
public final class TwakeWelcomeViewModel {
  public private(set) var isLoading = false
  public private(set) var errorMessage: String?

  public let configuration: SignInConfiguration
  @ObservationIgnored private let sso: SSOSignIn
  @ObservationIgnored private let onSignedIn: @MainActor (UserSession) -> Void
  @ObservationIgnored private let onUseCompanyServer: @MainActor () -> Void

  public init(
    configuration: SignInConfiguration, repository: any AuthenticationRepository,
    webAuthenticator: any WebAuthenticator, onSignedIn: @escaping @MainActor (UserSession) -> Void,
    onUseCompanyServer: @escaping @MainActor () -> Void
  ) {
    self.configuration = configuration
    self.sso = SSOSignIn(repository: repository, webAuthenticator: webAuthenticator)
    self.onSignedIn = onSignedIn
    self.onUseCompanyServer = onUseCompanyServer
  }

  public func signIn() async { await twakeID(signUp: false) }

  public func createTwakeID() async { await twakeID(signUp: true) }

  public func useCompanyServer() {
    guard !isLoading else { return }
    errorMessage = nil
    onUseCompanyServer()
  }

  private func twakeID(signUp: Bool) async {
    guard !isLoading else { return }
    errorMessage = nil
    guard let homeserver = configuration.workplaceHomeserver,
      let page = configuration.registrationSiteURL(signUp: signUp)
    else {
      errorMessage = SignInMessages.message(for: .unknown)
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      let session = try await sso.signIn(
        homeserver: homeserver, identityProviderId: nil,
        redirectURL: SignInConfiguration.registrationRedirectURL, page: page)
      onSignedIn(session)
    } catch {
      if case .authentication(let error) = error {
        errorMessage = SignInMessages.message(for: error)
      }
    }
  }
}
