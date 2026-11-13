import Domain
import Foundation

/// A hand-written `AuthenticationRepository` for tests (ADR 0010: fakes, no mocking library).
/// Each call is recorded, then answered with the scripted result. The password is recorded only so tests can check
/// what was sent; nothing here prints it.
public final class FakeAuthenticationRepository: AuthenticationRepository, @unchecked Sendable {
  public struct LoginCall: Equatable, Sendable {
    public let homeserver: URL
    public let username: String
    public let password: String

    public init(homeserver: URL, username: String, password: String) {
      self.homeserver = homeserver
      self.username = username
      self.password = password
    }
  }

  public struct StartSSOCall: Equatable, Sendable {
    public let homeserver: URL
    public let identityProviderId: String?
    public let redirectURL: URL

    public init(homeserver: URL, identityProviderId: String?, redirectURL: URL) {
      self.homeserver = homeserver
      self.identityProviderId = identityProviderId
      self.redirectURL = redirectURL
    }
  }

  private let lock = NSLock()
  private var _loginOptionsResult: Result<HomeserverLoginOptions, AuthenticationError>?
  private var _loginOptionsCalls: [String] = []
  private var _startSSOResult: Result<URL, AuthenticationError> = .failure(.unknown)
  private var _startSSOCalls: [StartSSOCall] = []
  private var _finishSSOResult: Result<UserSession, AuthenticationError> = .failure(.unknown)
  private var _finishSSOCalls: [URL] = []
  private var _cancelSSOCallCount = 0
  private var _loginResult: Result<UserSession, AuthenticationError> = .failure(.unknown)
  private var _restoreResult: Result<UserSession?, AuthenticationError> = .success(nil)
  private var _logoutResult: Result<Void, AuthenticationError> = .success(())
  private var _loginCalls: [LoginCall] = []
  private var _restoreCallCount = 0
  private var _logoutCallCount = 0
  private var _loginGate: CheckedContinuation<Void, Never>?
  private var _holdsLogin = false
  private var _logoutGate: CheckedContinuation<Void, Never>?
  private var _holdsLogout = false
  private var _restoreGate: CheckedContinuation<Void, Never>?
  private var _holdsRestore = false
  private var _savedSession: UserSession?
  private var _refusesLoginWhileSessionSaved = false

  public init() {}

  /// What `login` returns or throws.
  public var loginResult: Result<UserSession, AuthenticationError> {
    get { lock.withLock { _loginResult } }
    set { lock.withLock { _loginResult = newValue } }
  }

  /// What `loginOptions` returns or throws. Unset, it answers a password-only server at what was typed, so a test can
  /// walk to the password form.
  public var loginOptionsResult: Result<HomeserverLoginOptions, AuthenticationError>? {
    get { lock.withLock { _loginOptionsResult } }
    set { lock.withLock { _loginOptionsResult = newValue } }
  }

  /// What `startSSOLogin` returns or throws.
  public var startSSOResult: Result<URL, AuthenticationError> {
    get { lock.withLock { _startSSOResult } }
    set { lock.withLock { _startSSOResult = newValue } }
  }

  /// What `finishSSOLogin` returns or throws; a success also saves the session.
  public var finishSSOResult: Result<UserSession, AuthenticationError> {
    get { lock.withLock { _finishSSOResult } }
    set { lock.withLock { _finishSSOResult = newValue } }
  }

  public var loginOptionsCalls: [String] { lock.withLock { _loginOptionsCalls } }
  public var startSSOCalls: [StartSSOCall] { lock.withLock { _startSSOCalls } }
  public var finishSSOCalls: [URL] { lock.withLock { _finishSSOCalls } }
  public var cancelSSOCallCount: Int { lock.withLock { _cancelSSOCallCount } }

  /// What `restoreSession` returns or throws.
  public var restoreResult: Result<UserSession?, AuthenticationError> {
    get { lock.withLock { _restoreResult } }
    set { lock.withLock { _restoreResult = newValue } }
  }

  /// What `logout` throws, if anything.
  public var logoutResult: Result<Void, AuthenticationError> {
    get { lock.withLock { _logoutResult } }
    set { lock.withLock { _logoutResult = newValue } }
  }

  /// The session the fake keeps as saved: a successful `login` saves it and a successful `logout` clears it.
  public var savedSession: UserSession? {
    get { lock.withLock { _savedSession } }
    set { lock.withLock { _savedSession = newValue } }
  }

  /// When true, `login` throws `unknown` while `savedSession` is set, as `MatrixAuthenticationRepository` refuses a
  /// sign-in while a session is saved (one session per store).
  public var refusesLoginWhileSessionSaved: Bool {
    get { lock.withLock { _refusesLoginWhileSessionSaved } }
    set { lock.withLock { _refusesLoginWhileSessionSaved = newValue } }
  }

  public var loginCalls: [LoginCall] { lock.withLock { _loginCalls } }
  public var restoreCallCount: Int { lock.withLock { _restoreCallCount } }
  public var logoutCallCount: Int { lock.withLock { _logoutCallCount } }

  /// When true, `login` waits after recording its call until `releaseLogin()` is called, so a test can act while a
  /// sign-in is running.
  public func holdLogin() { lock.withLock { _holdsLogin = true } }

  /// Lets a held `login` finish.
  public func releaseLogin() {
    let gate = lock.withLock {
      _holdsLogin = false
      defer { _loginGate = nil }
      return _loginGate
    }
    gate?.resume()
  }

  /// When true, `logout` waits after recording its call until `releaseLogout()` is called, so a test can act while a
  /// logout is running.
  public func holdLogout() { lock.withLock { _holdsLogout = true } }

  /// Lets a held `logout` finish.
  public func releaseLogout() {
    let gate = lock.withLock {
      _holdsLogout = false
      defer { _logoutGate = nil }
      return _logoutGate
    }
    gate?.resume()
  }

  /// When true, `restoreSession` waits after recording its call until `releaseRestore()` is called, so a test can act
  /// while a restore is running.
  public func holdRestore() { lock.withLock { _holdsRestore = true } }

  /// Lets a held `restoreSession` finish.
  public func releaseRestore() {
    let gate = lock.withLock {
      _holdsRestore = false
      defer { _restoreGate = nil }
      return _restoreGate
    }
    gate?.resume()
  }

  public func login(homeserver: URL, username: String, password: String)
    async throws(AuthenticationError) -> UserSession
  {
    let holds = lock.withLock {
      _loginCalls.append(LoginCall(homeserver: homeserver, username: username, password: password))
      return _holdsLogin
    }
    if holds {
      await withCheckedContinuation { continuation in
        let stillHeld = lock.withLock {
          if _holdsLogin { _loginGate = continuation }
          return _holdsLogin
        }
        if !stillHeld { continuation.resume() }
      }
    }
    let refused = lock.withLock { _refusesLoginWhileSessionSaved && _savedSession != nil }
    if refused { throw .unknown }
    let session = try loginResult.get()
    savedSession = session
    return session
  }

  public func loginOptions(server: String) async throws(AuthenticationError)
    -> HomeserverLoginOptions
  {
    lock.withLock { _loginOptionsCalls.append(server) }
    if let result = loginOptionsResult { return try result.get() }
    guard let url = URL(string: server.contains("://") ? server : "https://\(server)") else {
      throw .invalidHomeserverURL
    }
    return HomeserverLoginOptions(
      homeserver: url, supportsPassword: true, supportsSSO: false, identityProviders: [],
      registrationSupported: false)
  }

  public func startSSOLogin(homeserver: URL, identityProviderId: String?, redirectURL: URL)
    async throws(AuthenticationError) -> URL
  {
    lock.withLock {
      _startSSOCalls.append(
        StartSSOCall(
          homeserver: homeserver, identityProviderId: identityProviderId, redirectURL: redirectURL))
    }
    return try startSSOResult.get()
  }

  public func finishSSOLogin(callbackURL: URL) async throws(AuthenticationError) -> UserSession {
    lock.withLock { _finishSSOCalls.append(callbackURL) }
    let session = try finishSSOResult.get()
    savedSession = session
    return session
  }

  public func cancelSSOLogin() async {
    lock.withLock { _cancelSSOCallCount += 1 }
  }

  public func restoreSession() async throws(AuthenticationError) -> UserSession? {
    let holds = lock.withLock {
      _restoreCallCount += 1
      return _holdsRestore
    }
    if holds {
      await withCheckedContinuation { continuation in
        let stillHeld = lock.withLock {
          if _holdsRestore { _restoreGate = continuation }
          return _holdsRestore
        }
        if !stillHeld { continuation.resume() }
      }
    }
    return try restoreResult.get()
  }

  public func logout() async throws(AuthenticationError) {
    let holds = lock.withLock {
      _logoutCallCount += 1
      return _holdsLogout
    }
    if holds {
      await withCheckedContinuation { continuation in
        let stillHeld = lock.withLock {
          if _holdsLogout { _logoutGate = continuation }
          return _holdsLogout
        }
        if !stillHeld { continuation.resume() }
      }
    }
    try logoutResult.get()
    savedSession = nil
  }
}
