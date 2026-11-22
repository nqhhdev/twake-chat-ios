import AppShared
import Domain
import Foundation
import MatrixRustSDK

/// `AuthenticationRepository` on the Matrix SDK: homeserver discovery, SSO and password sign-in as the Flutter app
/// does them, restore and logout. The session is saved in the Keychain and the SDK store in `storeDirectory`
/// (ADR 0007). Nothing here logs.
public actor MatrixAuthenticationRepository: AuthenticationRepository {
  private let storeDirectory: URL
  private let sessionStore: KeychainSessionStore
  private let lockHolderName: String
  private let initialDeviceName: String
  private let discovery: HomeserverDiscovery
  private var proxy: ClientProxy? {
    didSet {
      guard let proxy else { return }
      proxy.onSessionExpired { [weak self, weak proxy] in
        Task { await self?.sessionExpired(on: proxy) }
      }
    }
  }
  /// True while `logout()` runs: the server refusing the token then is the logout itself, not an expiry.
  private var isLoggingOut = false
  private let expirations = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
  private let signsOutWithoutStore: Bool
  private var pendingSSO: PendingSSOLogin?
  private var isSigningIn = false

  /// - Parameters:
  ///   - storeDirectory: The SDK store directory; the app passes `AppGroupContainer().sdkStoreDirectory()`.
  ///   - sessionStore: Where the session is saved.
  ///   - lockHolderName: This process's name in the SDK's cross-process store lock.
  ///   - initialDeviceName: The device name the server shows for a new password sign-in.
  ///   - discovery: Reads a homeserver's sign-in options.
  ///   - signsOutWithoutStore: The app passes `true`: a saved session whose SDK store is gone is signed out at
  ///     restore instead of being restored (see `restoreSession`). The extensions keep `false` and never sign out.
  public init(
    storeDirectory: URL, sessionStore: KeychainSessionStore, lockHolderName: String = "app",
    initialDeviceName: String = "Twake Chat iOS",
    discovery: HomeserverDiscovery = HomeserverDiscovery(),
    signsOutWithoutStore: Bool = false
  ) {
    self.signsOutWithoutStore = signsOutWithoutStore
    self.discovery = discovery
    self.storeDirectory = storeDirectory
    self.sessionStore = sessionStore
    self.lockHolderName = lockHolderName
    self.initialDeviceName = initialDeviceName
  }

  /// The client of the signed-in session, for the cards that sync and list rooms; `nil` before login or restore.
  public var clientProxy: ClientProxy? { proxy }

  public func loginOptions(server: String) async throws(AuthenticationError)
    -> HomeserverLoginOptions
  {
    try await discovery.loginOptions(server: server)
  }

  /// Signs in with a password. The SDK store holds one session, so a sign-in while one is saved, in progress or
  /// already running is refused with `unknown`; sign out first. Leftovers of an earlier failed sign-in or sign-out
  /// are deleted first.
  public func login(
    homeserver: URL, username: String, password: String
  ) async throws(AuthenticationError) -> UserSession {
    try beginSignIn()
    defer { isSigningIn = false }
    do {
      let (proxy, session) = try await ClientProxy.login(
        homeserver: homeserver, username: username, password: password,
        initialDeviceName: initialDeviceName, storeDirectory: storeDirectory,
        sessionStore: sessionStore, lockHolderName: lockHolderName)
      return try finishSignIn(proxy: proxy, session: session)
    } catch {
      throw UserSessionMapper.authenticationError(from: error)
    }
  }

  /// Builds a client on `homeserver`, starts an SSO sign-in and keeps it until `finishSSOLogin` or `cancelSSOLogin`.
  /// A sign-in started earlier and never finished is dropped first.
  public func startSSOLogin(
    homeserver: URL, identityProviderId: String?, redirectURL: URL
  ) async throws(AuthenticationError) -> URL {
    pendingSSO = nil
    try beginSignIn()
    defer { isSigningIn = false }
    do {
      let pending = try await ClientProxy.startSSO(
        homeserver: homeserver, identityProviderId: identityProviderId, redirectURL: redirectURL,
        storeDirectory: storeDirectory, sessionStore: sessionStore, lockHolderName: lockHolderName)
      guard let url = pending.url else { throw AuthenticationError.unknown }
      pendingSSO = pending
      return url
    } catch {
      throw UserSessionMapper.authenticationError(from: error)
    }
  }

  /// Finishes the started SSO sign-in. Without one, or when the callback has no `loginToken`, it throws.
  public func finishSSOLogin(callbackURL: URL) async throws(AuthenticationError) -> UserSession {
    guard let pending = pendingSSO, !isSigningIn, proxy == nil else { throw .unknown }
    guard Self.loginToken(in: callbackURL) != nil else { throw .invalidCredentials }
    isSigningIn = true
    defer { isSigningIn = false }
    do {
      let (proxy, session) = try await ClientProxy.finishSSO(pending, callbackURL: callbackURL)
      pendingSSO = nil
      return try finishSignIn(proxy: proxy, session: session)
    } catch {
      throw UserSessionMapper.authenticationError(from: error)
    }
  }

  public func cancelSSOLogin() async {
    pendingSSO = nil
  }

  /// The `loginToken` query item of an SSO callback, as the Flutter app reads it.
  static func loginToken(in callbackURL: URL) -> String? {
    URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems?
      .first { $0.name == "loginToken" }?.value.flatMap { $0.isEmpty ? nil : $0 }
  }

  /// Refuses a sign-in while one runs or a session exists, then clears what an earlier attempt left in the store.
  private func beginSignIn() throws(AuthenticationError) {
    guard !isSigningIn, proxy == nil else { throw .unknown }
    do {
      guard try sessionStore.load() == nil else { throw AuthenticationError.unknown }
      try removeStoreDirectory()
    } catch {
      throw UserSessionMapper.authenticationError(from: error)
    }
    isSigningIn = true
  }

  private func finishSignIn(proxy: ClientProxy, session: Session) throws -> UserSession {
    try sessionStore.save(try UserSessionMapper.storedSession(from: session))
    self.proxy = proxy
    return try UserSessionMapper.userSession(from: session)
  }

  /// The saved session, with a client restored on it. When a client is already running, it is kept: a second client
  /// on the same store is never built.
  ///
  /// The Keychain item outlives the app: after the app is deleted and installed again, the session is still saved but
  /// its SDK store, with the device's encryption keys, is gone. Restoring it would give the old device new keys, which
  /// other devices then refuse (twake-on-matrix #1036, PR #3516). With `signsOutWithoutStore`, such a session is
  /// signed out and removed instead, and the user signs in again as a new device.
  public func restoreSession() async throws(AuthenticationError) -> UserSession? {
    do {
      guard let stored = try sessionStore.load() else { return nil }
      if proxy != nil { return UserSessionMapper.userSession(from: stored) }
      if signsOutWithoutStore, !hasStore {
        // The server may not be reachable: the local session is removed all the same.
        try? await logout()
        return nil
      }
      proxy = try await ClientProxy.restore(
        session: UserSessionMapper.sdkSession(from: stored), storeDirectory: storeDirectory,
        sessionStore: sessionStore, lockHolderName: lockHolderName)
      return UserSessionMapper.userSession(from: stored)
    } catch {
      throw UserSessionMapper.authenticationError(from: error)
    }
  }

  /// Signs out on the server, then deletes the store directory and the Keychain item (ADR 0007). Both are deleted
  /// even when the server call fails; that failure is reported afterwards. After a cold launch with no client yet, a
  /// client is first restored on the saved session so the server still signs the device out.
  public func logout() async throws(AuthenticationError) {
    isLoggingOut = true
    defer { isLoggingOut = false }
    var serverError: (any Error)?
    do {
      if proxy == nil, let stored = try sessionStore.load() {
        proxy = try await ClientProxy.restore(
          session: UserSessionMapper.sdkSession(from: stored), storeDirectory: storeDirectory,
          sessionStore: sessionStore, lockHolderName: lockHolderName)
      }
      try await proxy?.logout()
    } catch {
      serverError = error
    }
    proxy = nil
    var localError: (any Error)?
    do {
      try removeStoreDirectory()
    } catch {
      localError = error
    }
    do {
      try sessionStore.delete()
    } catch {
      localError = localError ?? error
    }
    if let error = serverError ?? localError {
      throw UserSessionMapper.authenticationError(from: error)
    }
  }

  /// Reports an expiry only for the client in use, and not while the user is logging out.
  private func sessionExpired(on reporter: ClientProxy?) {
    guard let reporter, reporter === proxy, !isLoggingOut else { return }
    expirations.continuation.yield()
  }

  /// Whether the SDK store was ever opened in `storeDirectory`: `ClientProxy` creates its `data` folder first.
  private var hasStore: Bool {
    FileManager.default.fileExists(
      atPath: storeDirectory.appending(path: "data", directoryHint: .isDirectory)
        .path(percentEncoded: false))
  }

  private func removeStoreDirectory() throws {
    if FileManager.default.fileExists(atPath: storeDirectory.path(percentEncoded: false)) {
      try FileManager.default.removeItem(at: storeDirectory)
    }
  }
}

extension MatrixAuthenticationRepository: SessionExpiry {
  public func sessionExpirations() async -> AsyncStream<Void> {
    expirations.stream
  }
}

extension MatrixAuthenticationRepository: SyncLifecycle {
  public func pauseSync() async {
    await proxy?.pauseSync()
  }

  public func resumeSync() async {
    await proxy?.resumeSync()
  }
}
