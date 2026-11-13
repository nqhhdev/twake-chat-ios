import Domain
import Foundation
import Testing

/// The protocol is implementable by a hand-written fake with no SDK type (ADR 0006, ADR 0010), and its calls throw
/// `AuthenticationError` as a typed error.
struct AuthenticationRepositoryTests {
  private actor FakeAuthenticationRepository: AuthenticationRepository {
    private let password: String
    private var saved: UserSession?

    init(password: String) {
      self.password = password
    }

    func login(
      homeserver: URL, username: String, password: String
    ) async throws(AuthenticationError) -> UserSession {
      guard password == self.password else { throw .invalidCredentials }
      let session = UserSession(
        userId: "@\(username):example.org", deviceId: "DEVICE", homeserverURL: homeserver,
        accessToken: "access-secret", refreshToken: nil)
      saved = session
      return session
    }

    func loginOptions(server: String) async throws(AuthenticationError) -> HomeserverLoginOptions {
      throw .invalidHomeserverURL
    }

    func startSSOLogin(homeserver: URL, identityProviderId: String?, redirectURL: URL)
      async throws(AuthenticationError) -> URL
    {
      throw .unknown
    }

    func finishSSOLogin(callbackURL: URL) async throws(AuthenticationError) -> UserSession {
      throw .invalidCredentials
    }

    func cancelSSOLogin() async {}

    func restoreSession() async throws(AuthenticationError) -> UserSession? { saved }

    func logout() async throws(AuthenticationError) { saved = nil }
  }

  private let homeserver = URL(string: "https://matrix.example.org")!

  @Test func restoreWhenSignedOutReturnsNil() async throws {
    let repository: any AuthenticationRepository = FakeAuthenticationRepository(password: "pw")
    #expect(try await repository.restoreSession() == nil)
  }

  @Test func loginThenRestoreReturnsTheSession() async throws {
    let repository: any AuthenticationRepository = FakeAuthenticationRepository(password: "pw")
    let session = try await repository.login(
      homeserver: homeserver, username: "alice", password: "pw")
    #expect(session.homeserverURL == homeserver)
    #expect(try await repository.restoreSession() == session)
  }

  @Test func logoutThenRestoreReturnsNil() async throws {
    let repository: any AuthenticationRepository = FakeAuthenticationRepository(password: "pw")
    _ = try await repository.login(homeserver: homeserver, username: "alice", password: "pw")
    try await repository.logout()
    #expect(try await repository.restoreSession() == nil)
  }

  @Test func wrongPasswordThrowsTheTypedError() async {
    let repository: any AuthenticationRepository = FakeAuthenticationRepository(password: "pw")
    do {
      _ = try await repository.login(homeserver: homeserver, username: "alice", password: "wrong")
      Issue.record("login with a wrong password succeeded")
    } catch {
      // `error` is statically `AuthenticationError`: the protocol uses typed throws.
      #expect(error == .invalidCredentials)
    }
  }
}
