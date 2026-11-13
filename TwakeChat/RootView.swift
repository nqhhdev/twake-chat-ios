import Authentication
import ChatList
import Domain
import Foundation
import Observation
import SwiftUI

/// The root coordinator. At launch it restores the saved session, then hands over to the authentication flow, which
/// starts signed in or on TwakeWelcome. Signed in, it shows the chat list, whose Log out goes back to the
/// authentication flow: the root joins the two features, which do not know each other (ADR 0005).
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

  /// The authentication flow, created once the restore is done.
  private(set) var authentication: AuthenticationCoordinator?

  @ObservationIgnored private let repository: any AuthenticationRepository
  @ObservationIgnored private let roomList: (any RoomListRepository)?
  @ObservationIgnored private let signInConfiguration: SignInConfiguration
  @ObservationIgnored private let webAuthenticator: any WebAuthenticator

  /// - Parameters:
  ///   - roomList: The signed-in user's rooms; the app passes MatrixData's `RoomListProxy`. Tests that never reach the
  ///     chat list leave it out, and the signed-in screen is then empty.
  ///   - signInConfiguration: The build's sign-in URLs.
  ///   - webAuthenticator: Opens the SSO pages.
  init(
    repository: any AuthenticationRepository, roomList: (any RoomListRepository)? = nil,
    signInConfiguration: SignInConfiguration, webAuthenticator: any WebAuthenticator
  ) {
    self.repository = repository
    self.roomList = roomList
    self.signInConfiguration = signInConfiguration
    self.webAuthenticator = webAuthenticator
  }

  /// The chat list of the current signed-in state, kept so the screen keeps its state while it is shown.
  @ObservationIgnored private var chatList:
    (signedIn: SignedInViewModel, viewModel: ChatListViewModel)?

  /// The chat list for a signed-in state, created once per sign-in. Its Log out runs the signed-in state's logout,
  /// which shows the sign-in form when it succeeds.
  func chatList(for signedIn: SignedInViewModel) -> ChatListViewModel? {
    if let chatList, chatList.signedIn === signedIn { return chatList.viewModel }
    guard let roomList else { return nil }
    let viewModel = ChatListViewModel(repository: roomList) { [weak signedIn] in
      guard let signedIn else { return false }
      await signedIn.logOut()
      return signedIn.errorMessage == nil
    }
    chatList = (signedIn, viewModel)
    return viewModel
  }

  @ObservationIgnored private var started = false

  private func makeAuthentication(session: UserSession?) -> AuthenticationCoordinator {
    AuthenticationCoordinator(
      repository: repository, configuration: signInConfiguration,
      webAuthenticator: webAuthenticator,
      session: session)
  }

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
    authentication = makeAuthentication(session: session)
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
    authentication = makeAuthentication(session: nil)
  }
}

/// The app's root view: it only shows what the root coordinator holds.
struct RootView: View {
  let coordinator: RootCoordinator

  var body: some View {
    content
      .task { await coordinator.start() }
  }

  /// The screens come from the Authentication and ChatList feature packages.
  @ViewBuilder private var content: some View {
    if coordinator.state == .restoreFailed {
      RestoreFailedScreen(
        errorMessage: coordinator.logOutErrorMessage,
        retry: { Task { await coordinator.start() } },
        logOut: { Task { await coordinator.logOutAfterFailedRestore() } })
    } else if let authentication = coordinator.authentication {
      AuthenticationCoordinatorView(coordinator: authentication) { signedIn in
        if let chatList = coordinator.chatList(for: signedIn) {
          ChatListScreen(viewModel: chatList)
        }
      }
    } else {
      Color.clear
    }
  }
}
