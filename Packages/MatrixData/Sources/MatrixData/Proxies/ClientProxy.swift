import AppShared
import Foundation
import MatrixRustSDK

/// Wraps the SDK `Client` of one signed-in session (ADR 0006). Later cards add sync and the room list here.
/// Nothing public on it uses an SDK type.
///
/// The client's stores live under `storeDirectory`: production passes AppShared's App Group SDK directory (ADR 0007),
/// tests a temporary one. The store is opened with the SDK's cross-process lock so the app and the extension can
/// share it (ADR 0007); `lockHolderName` names this process. The pinned SDK refuses that lock without a session
/// delegate, so the client reads its session from `sessionStore` and saves refreshed tokens there
/// (`KeychainClientSessionDelegate`), never re-creating a session that sign-out deleted.
public final class ClientProxy: Sendable {
  let client: Client

  private init(client: Client) {
    self.client = client
  }

  /// The signed-in user's Matrix id.
  public var userId: String {
    get throws { try client.userId() }
  }

  /// The signed-in device's id.
  public var deviceId: String {
    get throws { try client.deviceId() }
  }

  #if DEBUG
    /// Signs in with a password and returns the proxy with the SDK session to save. Debug builds only (ADR 0019).
    /// The username goes to the server unchanged: a plain localpart or a full `@user:server`.
    static func login(
      homeserver: URL, username: String, password: String, initialDeviceName: String,
      storeDirectory: URL, sessionStore: KeychainSessionStore, lockHolderName: String
    ) async throws -> (ClientProxy, Session) {
      let builder = ClientBuilder()
        .serverNameOrHomeserverUrl(serverNameOrUrl: homeserver.absoluteString)
      let client = try await build(
        builder, storeDirectory: storeDirectory, sessionStore: sessionStore,
        lockHolderName: lockHolderName)
      try await client.login(
        username: username, password: password, initialDeviceName: initialDeviceName, deviceId: nil)
      return (ClientProxy(client: client), try client.session())
    }
  #endif

  /// Opens the store again and restores a saved session in a new client.
  static func restore(
    session: Session, storeDirectory: URL, sessionStore: KeychainSessionStore,
    lockHolderName: String
  ) async throws -> ClientProxy {
    let builder = ClientBuilder().homeserverUrl(url: session.homeserverUrl)
    let client = try await build(
      builder, storeDirectory: storeDirectory, sessionStore: sessionStore,
      lockHolderName: lockHolderName)
    try await client.restoreSession(session: session)
    return ClientProxy(client: client)
  }

  /// Signs this device out on the server. Removing the local store is the caller's job, so it happens even when this
  /// throws.
  func logout() async throws {
    try await client.logout()
  }

  private static func build(
    _ builder: ClientBuilder, storeDirectory: URL, sessionStore: KeychainSessionStore,
    lockHolderName: String
  ) async throws -> Client {
    let dataDirectory = storeDirectory.appending(path: "data", directoryHint: .isDirectory)
    let cacheDirectory = storeDirectory.appending(path: "cache", directoryHint: .isDirectory)
    for directory in [dataDirectory, cacheDirectory] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let delegate = KeychainClientSessionDelegate(sessionStore: sessionStore)
    return
      try await builder
      .sessionPaths(
        dataPath: dataDirectory.path(percentEncoded: false),
        cachePath: cacheDirectory.path(percentEncoded: false)
      )
      .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
      .crossProcessLockConfig(crossProcessLockConfig: .multiProcess(holderName: lockHolderName))
      .setSessionDelegate(sessionDelegate: delegate)
      .build()
  }
}

/// Lets the SDK read the saved session and save refreshed tokens in the Keychain, as the multi-process lock requires.
/// A save only updates the saved item of the same user and device and never adds one, so a callback that arrives after
/// sign-out deleted the item (from this or another process) is dropped. Nothing here logs; a save that fails is dropped,
/// and the next restore uses the last saved tokens.
final class KeychainClientSessionDelegate: ClientSessionDelegate {
  private let sessionStore: KeychainSessionStore

  init(sessionStore: KeychainSessionStore) {
    self.sessionStore = sessionStore
  }

  func retrieveSessionFromKeychain(userId: String) throws -> Session {
    guard let stored = try sessionStore.load(), stored.userId == userId else {
      throw ClientError.Generic(msg: "No saved session for this user", details: nil)
    }
    return UserSessionMapper.sdkSession(from: stored)
  }

  func saveSessionInKeychain(session: Session) {
    guard let stored = try? UserSessionMapper.storedSession(from: session) else { return }
    _ = try? sessionStore.saveRefreshedTokens(stored)
  }
}
