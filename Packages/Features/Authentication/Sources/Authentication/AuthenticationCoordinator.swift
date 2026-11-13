import Domain
import Foundation
import Observation
import SwiftUI

/// Owns the sign-in flow of the Flutter app: TwakeWelcome first, then the homeserver picker, the connect page or the
/// password form, then the signed-in screen, and back to TwakeWelcome after logout. It starts from the session the
/// app restored at launch, and creates each screen's view model.
@MainActor @Observable
public final class AuthenticationCoordinator {
  public enum Screen {
    case welcome(TwakeWelcomeViewModel)
    case homeserverPicker(HomeserverPickerViewModel)
    case connect(ConnectViewModel)
    case passwordLogin(PasswordLoginViewModel)
    case signedIn(SignedInViewModel)
  }

  public private(set) var screen: Screen

  @ObservationIgnored private let repository: any AuthenticationRepository
  @ObservationIgnored private let configuration: SignInConfiguration
  @ObservationIgnored private let webAuthenticator: any WebAuthenticator

  /// - Parameters:
  ///   - configuration: The build's sign-in settings.
  ///   - webAuthenticator: Opens the SSO pages.
  ///   - session: The session restored at launch, or `nil` to start on TwakeWelcome.
  public init(
    repository: any AuthenticationRepository, configuration: SignInConfiguration,
    webAuthenticator: any WebAuthenticator, session: UserSession?
  ) {
    self.repository = repository
    self.configuration = configuration
    self.webAuthenticator = webAuthenticator
    // The first screen needs the coordinator in its callbacks, which `self` cannot give before every stored property
    // is set; a placeholder is replaced at once.
    screen = .welcome(
      TwakeWelcomeViewModel(
        configuration: configuration, repository: repository, webAuthenticator: webAuthenticator,
        onSignedIn: { _ in }, onUseCompanyServer: {}))
    if let session {
      showSignedIn(session)
    } else {
      showWelcome()
    }
  }

  private func showWelcome() {
    screen = .welcome(
      TwakeWelcomeViewModel(
        configuration: configuration, repository: repository, webAuthenticator: webAuthenticator,
        onSignedIn: { [weak self] in self?.showSignedIn($0) },
        onUseCompanyServer: { [weak self] in self?.showHomeserverPicker() }))
  }

  private func showHomeserverPicker() {
    screen = .homeserverPicker(
      HomeserverPickerViewModel(
        defaultHomeserver: configuration.defaultHomeserver, repository: repository,
        webAuthenticator: webAuthenticator,
        onSignedIn: { [weak self] in self?.showSignedIn($0) },
        onConnect: { [weak self] in self?.showConnect($0) },
        onPassword: { [weak self] in self?.showPasswordLogin(homeserver: $0) },
        onBack: { [weak self] in self?.showWelcome() }))
  }

  private func showConnect(_ options: HomeserverLoginOptions) {
    screen = .connect(
      ConnectViewModel(
        options: options, repository: repository, webAuthenticator: webAuthenticator,
        onSignedIn: { [weak self] in self?.showSignedIn($0) },
        onBack: { [weak self] in self?.showHomeserverPicker() }))
  }

  private func showPasswordLogin(homeserver: URL) {
    screen = .passwordLogin(
      PasswordLoginViewModel(
        repository: repository, defaultHomeserver: homeserver,
        onSignedIn: { [weak self] in self?.showSignedIn($0) },
        onBack: { [weak self] in self?.showHomeserverPicker() }))
  }

  private func showSignedIn(_ session: UserSession) {
    screen = .signedIn(
      SignedInViewModel(
        session: session, repository: repository,
        onLoggedOut: { [weak self] in self?.showWelcome() }))
  }
}

/// Shows the coordinator's current screen. The signed-in content comes from the app, which joins this feature to the
/// chat list (ADR 0005: a feature does not import another feature).
public struct AuthenticationCoordinatorView<SignedInContent: View>: View {
  let coordinator: AuthenticationCoordinator
  let signedIn: (SignedInViewModel) -> SignedInContent

  public init(
    coordinator: AuthenticationCoordinator,
    @ViewBuilder signedIn: @escaping (SignedInViewModel) -> SignedInContent
  ) {
    self.coordinator = coordinator
    self.signedIn = signedIn
  }

  public var body: some View {
    switch coordinator.screen {
    case .welcome(let viewModel): TwakeWelcomeScreen(viewModel: viewModel)
    case .homeserverPicker(let viewModel): HomeserverPickerScreen(viewModel: viewModel)
    case .connect(let viewModel): ConnectScreen(viewModel: viewModel)
    case .passwordLogin(let viewModel): PasswordLoginScreen(viewModel: viewModel)
    case .signedIn(let viewModel): signedIn(viewModel)
    }
  }
}
