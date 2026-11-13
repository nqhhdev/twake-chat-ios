import Domain
import Foundation
import Observation

/// "Use your company server", as the Flutter app's `HomeserverPicker` (homeserver_picker.dart:146-243): Continue reads
/// the server's sign-in options, then goes straight to its single SSO provider, to the connect page, or to the password
/// form on a server without SSO.
@MainActor @Observable
public final class HomeserverPickerViewModel {
  public var server: String
  public private(set) var isLoading = false
  /// Set when the server could not be found; the field then shows "Wrong server name" and the explanation.
  public private(set) var isWrongServerName = false
  public private(set) var errorMessage: String?

  @ObservationIgnored private let repository: any AuthenticationRepository
  @ObservationIgnored private let sso: SSOSignIn
  @ObservationIgnored private let onSignedIn: @MainActor (UserSession) -> Void
  @ObservationIgnored private let onConnect: @MainActor (HomeserverLoginOptions) -> Void
  @ObservationIgnored private let onPassword: @MainActor (URL) -> Void
  @ObservationIgnored private let onBack: @MainActor () -> Void

  public init(
    defaultHomeserver: URL?, repository: any AuthenticationRepository,
    webAuthenticator: any WebAuthenticator,
    onSignedIn: @escaping @MainActor (UserSession) -> Void,
    onConnect: @escaping @MainActor (HomeserverLoginOptions) -> Void,
    onPassword: @escaping @MainActor (URL) -> Void, onBack: @escaping @MainActor () -> Void
  ) {
    self.server = defaultHomeserver.map(Self.fieldText) ?? ""
    self.repository = repository
    self.sso = SSOSignIn(repository: repository, webAuthenticator: webAuthenticator)
    self.onSignedIn = onSignedIn
    self.onConnect = onConnect
    self.onPassword = onPassword
    self.onBack = onBack
  }

  /// The field shows a plain `https` homeserver as its server name, as the Flutter app's `default_homeserver`, and
  /// any other address in full.
  static func fieldText(for homeserver: URL) -> String {
    guard homeserver.scheme == "https", homeserver.port == nil, let host = homeserver.host(),
      homeserver.path().isEmpty || homeserver.path() == "/"
    else { return homeserver.absoluteString }
    return host
  }

  public func back() {
    guard !isLoading else { return }
    onBack()
  }

  public func continueTapped() async {
    guard !isLoading else { return }
    errorMessage = nil
    isWrongServerName = false
    isLoading = true
    defer { isLoading = false }
    let options: HomeserverLoginOptions
    do {
      options = try await repository.loginOptions(server: server)
    } catch {
      if error == .invalidHomeserverURL {
        isWrongServerName = true
      } else {
        errorMessage = SignInMessages.message(for: error)
      }
      return
    }
    switch options.signInRoute {
    case .password: onPassword(options.homeserver)
    case .connect: onConnect(options)
    case .sso(let provider):
      do {
        let session = try await sso.signIn(
          homeserver: options.homeserver, identityProviderId: provider.id,
          redirectURL: SignInConfiguration.ssoRedirectURL)
        onSignedIn(session)
      } catch {
        if case .authentication(let error) = error {
          errorMessage = SignInMessages.message(for: error)
        }
      }
    }
  }
}
