import Domain
import Foundation
import Observation

/// The password sign-in form, for a homeserver without SSO. The checks follow the Flutter app's
/// `lib/pages/login/login.dart` `login()`: the last error is cleared first, a tap while a sign-in runs does nothing,
/// and an empty username or password shows its own message and does not submit. The password is never logged.
@MainActor @Observable
public final class PasswordLoginViewModel {
  public var homeserver: String
  public var username = ""
  public var password = ""
  public private(set) var isLoading = false
  public private(set) var usernameError: String?
  public private(set) var passwordError: String?
  public private(set) var errorMessage: String?

  @ObservationIgnored private let repository: any AuthenticationRepository
  @ObservationIgnored private let onSignedIn: @MainActor (UserSession) -> Void
  @ObservationIgnored private let onBack: (@MainActor () -> Void)?

  /// - Parameters:
  ///   - defaultHomeserver: Prefills the homeserver field; it comes from the app's build configuration.
  ///   - onSignedIn: Called with the new session after a successful sign-in.
  ///   - onBack: Goes back to the homeserver picker; `nil` hides the back button.
  public init(
    repository: any AuthenticationRepository, defaultHomeserver: URL?,
    onSignedIn: @escaping @MainActor (UserSession) -> Void, onBack: (@MainActor () -> Void)? = nil
  ) {
    self.onBack = onBack
    self.repository = repository
    self.homeserver = defaultHomeserver?.absoluteString ?? ""
    self.onSignedIn = onSignedIn
  }

  public var canGoBack: Bool { onBack != nil }

  public func back() {
    guard !isLoading else { return }
    onBack?()
  }

  public func signIn() async {
    errorMessage = nil
    guard !isLoading else { return }
    usernameError = username.isEmpty ? Self.emptyUsernameMessage : nil
    passwordError = password.isEmpty ? Self.emptyPasswordMessage : nil
    guard usernameError == nil, passwordError == nil else { return }
    guard let url = URL(string: homeserver), url.scheme != nil, url.host() != nil else {
      errorMessage = Self.message(for: .invalidHomeserverURL)
      return
    }

    isLoading = true
    defer { isLoading = false }
    do {
      let session = try await repository.login(
        homeserver: url, username: username, password: password)
      onSignedIn(session)
    } catch {
      errorMessage = Self.message(for: error)
    }
  }

  static let emptyUsernameMessage = "Please enter your Matrix Id or username"
  static let emptyPasswordMessage = "Please enter your password"

  static func message(for error: AuthenticationError) -> String {
    switch error {
    case .invalidCredentials: "Invalid username or password"
    case .serverUnreachable: "No connection to the server"
    case .invalidHomeserverURL: "This is not a valid Matrix homeserver address"
    case .unknown: "Oops, something went wrong…"
    }
  }
}
