import AppShared
import Foundation
import MatrixRustSDK

/// Wraps the SDK `Client` of one signed-in session and its sync service (ADR 0006). Nothing public on it uses an SDK
/// type.
///
/// The client's stores live under `storeDirectory`: production passes AppShared's App Group SDK directory (ADR 0007),
/// tests a temporary one. The store is opened with the SDK's cross-process lock so the app and the extension can
/// share it (ADR 0007); `lockHolderName` names this process. The pinned SDK refuses that lock without a session
/// delegate, so the client reads its session from `sessionStore` and saves refreshed tokens there
/// (`KeychainClientSessionDelegate`), never re-creating a session that sign-out deleted.
public final class ClientProxy: Sendable {
  let client: Client
  private let sync = SyncServiceHolder()

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

  /// Starts the client's sync service once and returns its room list service; later calls reuse the running service.
  func startSync() async throws -> RoomListService {
    try await sync.start(client: client).roomListService()
  }

  /// Keeps SDK objects that feed on the running sync (a room list, its controller and its entries `TaskHandle`) until
  /// sync stops, which cancels the handle and releases them while the client is still alive: the SDK aborts the
  /// process when a room list is freed after its client. Returns `false`, keeping nothing, when sync is not running
  /// (it stopped meanwhile); the caller then cancels and drops them itself.
  func keepWhileSyncing(_ objects: SyncBoundObjects) async -> Bool {
    await sync.keep(objects)
  }

  /// Stops the sync service, after releasing what `keepWhileSyncing` kept. Does nothing when it is not running.
  func stopSync() async {
    await sync.stop()
  }

  /// Stops sync for good, then signs this device out on the server. Removing the local store is the caller's job, so it
  /// happens even when this throws; sync is stopped first, and cannot start again on this client, so nothing writes to
  /// the store while it is removed.
  func logout() async throws {
    await sync.close()
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

/// SDK objects that live only while sync runs: `entries` is cancelled and `objects` released when sync stops.
struct SyncBoundObjects: Sendable {
  let entries: TaskHandle
  let objects: [any Sendable]
}

/// Builds and starts at most one `SyncService` per client, also when two callers start it together, and stops it.
/// Stopping first releases the objects kept with `keep(_:)`. Once closed (logout), it stops and never starts again.
private actor SyncServiceHolder {
  private var running: Task<SyncService, any Error>?
  private var kept: [SyncBoundObjects] = []
  private var isClosed = false

  struct Closed: Error {}

  func keep(_ objects: SyncBoundObjects) -> Bool {
    guard running != nil else { return false }
    kept.append(objects)
    return true
  }

  func start(client: Client) async throws -> SyncService {
    guard !isClosed else { throw Closed() }
    let task =
      running
      ?? Task {
        let service = try await client.syncService().finish()
        await service.start()
        return service
      }
    running = task
    do {
      return try await task.value
    } catch {
      if running == task { running = nil }
      throw error
    }
  }

  func stop() async {
    for objects in kept { objects.entries.cancel() }
    kept = []
    guard let task = running else { return }
    running = nil
    if let service = try? await task.value { await service.stop() }
  }

  /// Stops sync and refuses every later `start`, so no sync service is built while the store is being removed.
  func close() async {
    isClosed = true
    await stop()
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
