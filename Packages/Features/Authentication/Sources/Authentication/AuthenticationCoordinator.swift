// Debug only (ADR 0019): a Release build of the app must not contain the password sign-in flow.
#if DEBUG
  import Domain
  import Foundation
  import Observation
  import SwiftUI

  /// Owns the authentication flow: the password form, then the signed-in screen, and back to the form after logout.
  /// It starts from the session the app restored at launch, and creates each screen's view model.
  @MainActor @Observable
  public final class AuthenticationCoordinator {
    public enum Screen {
      case passwordLogin(PasswordLoginViewModel)
      case signedIn(SignedInViewModel)
    }

    public private(set) var screen: Screen

    @ObservationIgnored private let repository: any AuthenticationRepository
    @ObservationIgnored private let defaultHomeserver: URL?

    /// - Parameters:
    ///   - session: The session restored at launch, or `nil` to start on the password form.
    ///   - defaultHomeserver: Prefills the form's homeserver field.
    public init(
      repository: any AuthenticationRepository, defaultHomeserver: URL?, session: UserSession?
    ) {
      self.repository = repository
      self.defaultHomeserver = defaultHomeserver
      // The first screen is built before `self` exists, so its callback reaches the coordinator through this weak
      // reference, set once initialization is done.
      weak var coordinator: AuthenticationCoordinator?
      if let session {
        screen = Self.signedInScreen(session, repository) { coordinator?.showPasswordLogin() }
      } else {
        screen = Self.passwordLoginScreen(repository, defaultHomeserver) {
          coordinator?.showSignedIn($0)
        }
      }
      coordinator = self
    }

    private func showPasswordLogin() {
      screen = Self.passwordLoginScreen(repository, defaultHomeserver) { [weak self] in
        self?.showSignedIn($0)
      }
    }

    private func showSignedIn(_ session: UserSession) {
      screen = Self.signedInScreen(session, repository) { [weak self] in self?.showPasswordLogin() }
    }

    private static func passwordLoginScreen(
      _ repository: any AuthenticationRepository, _ defaultHomeserver: URL?,
      onSignedIn: @escaping @MainActor (UserSession) -> Void
    ) -> Screen {
      .passwordLogin(
        PasswordLoginViewModel(
          repository: repository, defaultHomeserver: defaultHomeserver, onSignedIn: onSignedIn))
    }

    private static func signedInScreen(
      _ session: UserSession, _ repository: any AuthenticationRepository,
      onLoggedOut: @escaping @MainActor () -> Void
    ) -> Screen {
      .signedIn(
        SignedInViewModel(session: session, repository: repository, onLoggedOut: onLoggedOut))
    }
  }

  /// Shows the coordinator's current screen.
  public struct AuthenticationCoordinatorView: View {
    let coordinator: AuthenticationCoordinator

    public init(coordinator: AuthenticationCoordinator) {
      self.coordinator = coordinator
    }

    public var body: some View {
      switch coordinator.screen {
      case .passwordLogin(let viewModel): PasswordLoginScreen(viewModel: viewModel)
      case .signedIn(let viewModel): SignedInScreen(viewModel: viewModel)
      }
    }
  }
#endif
