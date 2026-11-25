import AppShared
import Domain
import Foundation
import MatrixRustSDK

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
  private var isLoggingOut = false
  private let expirations = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
  private let signsOutWithoutStore: Bool
  private var pendingSSO: PendingSSOLogin?
  private var isSigningIn = false
  private let onSessionChange: @Sendable (SessionChange) -> Void

  public init(
    storeDirectory: URL, sessionStore: KeychainSessionStore, lockHolderName: String = "app",
    initialDeviceName: String = "Twake Chat iOS",
    discovery: HomeserverDiscovery = HomeserverDiscovery(),
    signsOutWithoutStore: Bool = false,
    onSessionChange: @escaping @Sendable (SessionChange) -> Void = { _ in }
  ) {
    self.onSessionChange = onSessionChange
    self.signsOutWithoutStore = signsOutWithoutStore
    self.discovery = discovery
    self.storeDirectory = storeDirectory
    self.sessionStore = sessionStore
    self.lockHolderName = lockHolderName
    self.initialDeviceName = initialDeviceName
  }

  public var clientProxy: ClientProxy? { proxy }

  public func loginOptions(server: String) async throws(AuthenticationError)
    -> HomeserverLoginOptions
  {
    try await discovery.loginOptions(server: server)
  }

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

  public func finishSSOLogin(callbackURL: URL) async throws(AuthenticationError) -> UserSession {
    guard let pending = pendingSSO, !isSigningIn, proxy == nil else { throw .unknown }
    guard Self.loginToken(in: callbackURL) != nil else { throw .invalidCredentials }
    isSigningIn = true
    defer { isSigningIn = false }
    do {
      let (proxy, session) = try await ClientProxy.finishSSO(pending, callbackURL: callbackURL)
      pendingSSO = nil
      let issuer = await discovery.authenticationIssuer(
        homeserver: try UserSessionMapper.userSession(from: session).homeserverURL)
      return try finishSignIn(proxy: proxy, session: session, authenticationIssuer: issuer)
    } catch {
      throw UserSessionMapper.authenticationError(from: error)
    }
  }

  public func cancelSSOLogin() async {
    pendingSSO = nil
  }

  static func loginToken(in callbackURL: URL) -> String? {
    URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems?
      .first { $0.name == "loginToken" }?.value.flatMap { $0.isEmpty ? nil : $0 }
  }

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

  private func finishSignIn(proxy: ClientProxy, session: Session, authenticationIssuer: URL? = nil)
    throws -> UserSession
  {
    let stored = try UserSessionMapper.storedSession(
      from: session, authenticationIssuer: authenticationIssuer)
    try sessionStore.save(stored)
    self.proxy = proxy
    onSessionChange(.signedIn(userId: stored.userId))
    return try UserSessionMapper.userSession(
      from: session, authenticationIssuer: authenticationIssuer)
  }

  public func restoreSession() async throws(AuthenticationError) -> UserSession? {
    do {
      guard let stored = try sessionStore.load() else { return nil }
      if proxy != nil { return UserSessionMapper.userSession(from: stored) }
      if signsOutWithoutStore, !hasStore {
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

  public func logout() async throws(AuthenticationError) {
    isLoggingOut = true
    defer { isLoggingOut = false }
    let signedOutUserId = try? sessionStore.load()?.userId
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
      if let signedOutUserId { onSessionChange(.signedOut(userId: signedOutUserId)) }
    } catch {
      localError = localError ?? error
    }
    if let error = serverError ?? localError {
      throw UserSessionMapper.authenticationError(from: error)
    }
  }

  private func sessionExpired(on reporter: ClientProxy?) {
    guard let reporter, reporter === proxy, !isLoggingOut else { return }
    expirations.continuation.yield()
  }

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

public enum SessionChange: Sendable, Equatable {
  case signedIn(userId: String)
  case signedOut(userId: String)
}
