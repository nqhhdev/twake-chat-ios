import AppShared
import Domain
import Foundation

/// `AuthenticationRepository` on the Matrix SDK: password login (Debug builds, ADR 0019), restore and logout.
/// The session is saved in the Keychain and the SDK store in `storeDirectory` (ADR 0007). Nothing here logs.
public actor MatrixAuthenticationRepository: AuthenticationRepository {
  private let storeDirectory: URL
  private let sessionStore: KeychainSessionStore
  private let lockHolderName: String
  private let initialDeviceName: String
  private var proxy: ClientProxy?
  private var isSigningIn = false

  /// - Parameters:
  ///   - storeDirectory: The SDK store directory; the app passes `AppGroupContainer().sdkStoreDirectory()`.
  ///   - sessionStore: Where the session is saved.
  ///   - lockHolderName: This process's name in the SDK's cross-process store lock.
  ///   - initialDeviceName: The device name the server shows for a new sign-in.
  public init(
    storeDirectory: URL, sessionStore: KeychainSessionStore, lockHolderName: String = "app",
    initialDeviceName: String = "Twake Chat iOS"
  ) {
    self.storeDirectory = storeDirectory
    self.sessionStore = sessionStore
    self.lockHolderName = lockHolderName
    self.initialDeviceName = initialDeviceName
  }

  /// The client of the signed-in session, for the cards that sync and list rooms; `nil` before login or restore.
  public var clientProxy: ClientProxy? { proxy }

  #if DEBUG
    /// Signs in with a password (Debug builds only, ADR 0019). The SDK store holds one session, so a sign-in while one
    /// is saved, in progress or already running is refused with `unknown`; sign out first. Leftovers of an earlier
    /// failed sign-in or sign-out are deleted first.
    public func login(
      homeserver: URL, username: String, password: String
    ) async throws(AuthenticationError) -> UserSession {
      guard !isSigningIn, proxy == nil else { throw .unknown }
      isSigningIn = true
      defer { isSigningIn = false }
      do {
        guard try sessionStore.load() == nil else { throw AuthenticationError.unknown }
        try removeStoreDirectory()
        let (proxy, session) = try await ClientProxy.login(
          homeserver: homeserver, username: username, password: password,
          initialDeviceName: initialDeviceName, storeDirectory: storeDirectory,
          sessionStore: sessionStore, lockHolderName: lockHolderName)
        try sessionStore.save(try UserSessionMapper.storedSession(from: session))
        self.proxy = proxy
        return try UserSessionMapper.userSession(from: session)
      } catch {
        throw UserSessionMapper.authenticationError(from: error)
      }
    }
  #else
    /// Release builds contain no password sign-in code (ADR 0019): sign-in is SSO-only (ADR 0008).
    public func login(
      homeserver: URL, username: String, password: String
    ) async throws(AuthenticationError) -> UserSession {
      throw .unknown
    }
  #endif

  /// The saved session, with a client restored on it. When a client is already running, it is kept: a second client
  /// on the same store is never built.
  public func restoreSession() async throws(AuthenticationError) -> UserSession? {
    do {
      guard let stored = try sessionStore.load() else { return nil }
      if proxy != nil { return UserSessionMapper.userSession(from: stored) }
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

  private func removeStoreDirectory() throws {
    if FileManager.default.fileExists(atPath: storeDirectory.path(percentEncoded: false)) {
      try FileManager.default.removeItem(at: storeDirectory)
    }
  }
}
