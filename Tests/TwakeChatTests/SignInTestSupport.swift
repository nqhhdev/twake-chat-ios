import Authentication
import Domain
import Foundation

@testable import TwakeChat

/// A web authenticator for tests that never opens a page: every SSO attempt ends as if the user closed it.
struct ClosedWebAuthenticator: WebAuthenticator {
  @MainActor func authenticate(url: URL, callbackScheme: String) async throws(WebAuthenticationError) -> URL {
    throw .cancelled
  }
}

extension RootCoordinator {
  /// The root the composition root builds, with `defaultHomeserver` prefilled in the company-server field and no
  /// Twake ID URLs.
  convenience init(
    repository: any AuthenticationRepository, roomList: (any RoomListRepository)? = nil, defaultHomeserver: URL?
  ) {
    self.init(
      repository: repository, roomList: roomList,
      signInConfiguration: SignInConfiguration(
        registrationURL: nil, workplaceHomeserver: nil, defaultHomeserver: defaultHomeserver,
        privacyURL: URL(string: "https://twake.app/policy")!),
      webAuthenticator: ClosedWebAuthenticator())
  }
}

/// Whether the root shows TwakeWelcome, the signed-out first screen.
@MainActor
func isSignedOut(_ root: RootCoordinator) -> Bool {
  if case .welcome = root.authentication?.screen { true } else { false }
}

/// Walks from TwakeWelcome through "Use your company server" and Continue with the prefilled server to the password
/// form; `nil` when the flow does not end there (a server with SSO, or an error).
@MainActor
func passwordForm(of root: RootCoordinator) async -> PasswordLoginViewModel? {
  guard let authentication = root.authentication else { return nil }
  if case .welcome(let welcome) = authentication.screen { welcome.useCompanyServer() }
  if case .homeserverPicker(let picker) = authentication.screen { await picker.continueTapped() }
  if case .passwordLogin(let form) = authentication.screen { return form }
  return nil
}
