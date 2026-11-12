import Domain
import Foundation
import Observation
import SwiftUI

#if DEBUG
  import Authentication
#endif

/// The root coordinator. At launch it restores the saved session, then hands over to the authentication flow, which
/// starts signed in or on the sign-in form. Sign-in exists only in Debug builds (ADR 0019); a Release build shows an
/// empty screen until SSO lands (ADR 0008).
@MainActor @Observable
final class RootCoordinator {
  enum State: Equatable {
    case restoring
    /// The result of the launch restore: the saved session, or `nil` when nobody is signed in or restoring failed.
    case restored(UserSession?)
    /// The saved session could not be restored (for example the homeserver did not answer, or the Keychain or the SDK
    /// store was not available yet). The session and its store are kept, as the Flutter app keeps them when a launch
    /// fails offline; the user tries again. Nothing here deletes a saved session: only Log out does.
    case restoreFailed
  }

  private(set) var state: State = .restoring
  /// Shown on the restore-failed screen when Log out failed and the session is still saved on this device.
  private(set) var logOutErrorMessage: String?

  #if DEBUG
    /// The authentication flow, created once the restore is done.
    private(set) var authentication: AuthenticationCoordinator?
  #endif

  @ObservationIgnored private let repository: any AuthenticationRepository
  @ObservationIgnored private let defaultHomeserver: URL?

  /// - Parameter defaultHomeserver: Prefills the Debug sign-in form; Release passes `nil`.
  init(repository: any AuthenticationRepository, defaultHomeserver: URL?) {
    self.repository = repository
    self.defaultHomeserver = defaultHomeserver
  }

  @ObservationIgnored private var started = false

  /// Restores the saved session once, also when several windows start it together. A restore error keeps the saved
  /// session and its store and sets `restoreFailed`: calling `start()` again tries once more. The Domain errors cannot
  /// tell a session the server rejected from a fault that passes (the mapper turns both into `unknown`), so the root
  /// never clears the session on its own; Log out (`logOutAfterFailedRestore()`) is the user's way out. While a restore
  /// runs the state is `restoring`, so Log out cannot run beside it.
  func start() async {
    guard !started else { return }
    started = true
    state = .restoring
    logOutErrorMessage = nil
    let session: UserSession?
    do {
      session = try await repository.restoreSession()
    } catch {
      state = .restoreFailed
      started = false
      return
    }
    state = .restored(session)
    #if DEBUG
      authentication = AuthenticationCoordinator(
        repository: repository, defaultHomeserver: defaultHomeserver, session: session)
    #endif
  }

  /// The way out of `restoreFailed` when the error does not pass: signs out (the repository clears the local session
  /// even when the server cannot be told) and shows the sign-in form. While it runs, `start()` does nothing. When the
  /// repository reports an error the session may still be saved, so the screen stays with an error and the user can
  /// try again, as on the signed-in screen: the user is never shown as signed out while a session is still saved.
  func logOutAfterFailedRestore() async {
    guard state == .restoreFailed, !started else { return }
    started = true
    logOutErrorMessage = nil
    do {
      try await repository.logout()
    } catch {
      logOutErrorMessage = "Could not log out. Please try again."
      started = false
      return
    }
    state = .restored(nil)
    #if DEBUG
      authentication = AuthenticationCoordinator(
        repository: repository, defaultHomeserver: defaultHomeserver, session: nil)
    #endif
  }
}

/// The app's root view: it only shows what the root coordinator holds.
struct RootView: View {
  let coordinator: RootCoordinator

  var body: some View {
    content
      .task { await coordinator.start() }
  }

  /// Every screen comes from the Authentication feature package; Release, which cannot sign in, stays empty.
  @ViewBuilder private var content: some View {
    #if DEBUG
      if coordinator.state == .restoreFailed {
        RestoreFailedScreen(
          errorMessage: coordinator.logOutErrorMessage,
          retry: { Task { await coordinator.start() } },
          logOut: { Task { await coordinator.logOutAfterFailedRestore() } })
      } else if let authentication = coordinator.authentication {
        AuthenticationCoordinatorView(coordinator: authentication)
      } else {
        Color.clear
      }
    #else
      Color.clear
    #endif
  }
}
