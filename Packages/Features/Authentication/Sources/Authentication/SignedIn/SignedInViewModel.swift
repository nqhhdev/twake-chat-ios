import Domain
import Foundation
import Observation

/// The signed-in state: the user id and the log-out action. The app shows the chat list for it (TWAK-66) and wires the
/// chat list's Log out button to `logOut()`.
@MainActor @Observable
public final class SignedInViewModel {
  public let userId: String
  public private(set) var isLoggingOut = false
  /// Shown when logout failed and the session is still saved on this device.
  public private(set) var errorMessage: String?

  @ObservationIgnored private let repository: any AuthenticationRepository
  @ObservationIgnored private let onLoggedOut: @MainActor () -> Void

  /// - Parameter onLoggedOut: Called once the repository reports a logout without error. When logout fails, the
  ///   screen stays with an error and the user can try again: the repository deletes the local session even when the
  ///   server call fails, so trying again then succeeds at once, and while the local removal fails the user is never
  ///   shown as signed out with a session still saved.
  public init(
    session: UserSession, repository: any AuthenticationRepository,
    onLoggedOut: @escaping @MainActor () -> Void
  ) {
    self.userId = session.userId
    self.repository = repository
    self.onLoggedOut = onLoggedOut
  }

  public func logOut() async {
    guard !isLoggingOut else { return }
    isLoggingOut = true
    defer { isLoggingOut = false }
    errorMessage = nil
    do {
      try await repository.logout()
    } catch {
      errorMessage = "Could not log out. Please try again."
      return
    }
    onLoggedOut()
  }
}
