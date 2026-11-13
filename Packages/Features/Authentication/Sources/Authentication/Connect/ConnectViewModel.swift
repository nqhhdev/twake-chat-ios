import Domain
import Foundation
import Observation

/// The Flutter app's `ConnectPage` (connect_page_view.dart): the homeserver's host as the title and one button per SSO
/// identity provider; a tap signs in through that provider.
@MainActor @Observable
public final class ConnectViewModel {
  public let options: HomeserverLoginOptions
  public private(set) var isLoading = false
  public private(set) var errorMessage: String?

  @ObservationIgnored private let sso: SSOSignIn
  @ObservationIgnored private let onSignedIn: @MainActor (UserSession) -> Void
  @ObservationIgnored private let onBack: @MainActor () -> Void

  public init(
    options: HomeserverLoginOptions, repository: any AuthenticationRepository,
    webAuthenticator: any WebAuthenticator, onSignedIn: @escaping @MainActor (UserSession) -> Void,
    onBack: @escaping @MainActor () -> Void
  ) {
    self.options = options
    self.sso = SSOSignIn(repository: repository, webAuthenticator: webAuthenticator)
    self.onSignedIn = onSignedIn
    self.onBack = onBack
  }

  public var title: String { options.homeserver.host() ?? "" }

  /// The providers to show; a server with SSO and no listed provider gets one plain SSO button.
  public var providers: [HomeserverLoginOptions.IdentityProvider] {
    options.identityProviders.isEmpty && options.supportsSSO
      ? [.init(id: "", name: "Sign in with one click")] : options.identityProviders
  }

  public func back() {
    guard !isLoading else { return }
    onBack()
  }

  public func signIn(with provider: HomeserverLoginOptions.IdentityProvider) async {
    guard !isLoading else { return }
    errorMessage = nil
    isLoading = true
    defer { isLoading = false }
    do {
      let session = try await sso.signIn(
        homeserver: options.homeserver, identityProviderId: provider.id.isEmpty ? nil : provider.id,
        redirectURL: SignInConfiguration.ssoRedirectURL)
      onSignedIn(session)
    } catch {
      if case .authentication(let error) = error {
        errorMessage = SignInMessages.message(for: error)
      }
    }
  }
}
