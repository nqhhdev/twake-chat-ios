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
    // Local echoes of pictures, videos and files then carry how much is uploaded, for the progress ring.
    client.enableSendQueueUploadProgress(enable: true)
  }

  /// The signed-in user's Matrix id.
  public var userId: String {
    get throws { try client.userId() }
  }

  /// The signed-in device's id.
  public var deviceId: String {
    get throws { try client.deviceId() }
  }

  /// Signs in with a password and returns the proxy with the SDK session to save. The Flutter app offers it only on
  /// a homeserver without SSO. The username goes to the server unchanged: a plain localpart or a full `@user:server`.
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

  /// Builds a client on `homeserver` and starts an SSO sign-in on it. The returned sign-in holds the client until
  /// `finishSSO` turns it into a proxy.
  static func startSSO(
    homeserver: URL, identityProviderId: String?, redirectURL: URL, storeDirectory: URL,
    sessionStore: KeychainSessionStore, lockHolderName: String
  ) async throws -> PendingSSOLogin {
    let builder = ClientBuilder()
      .serverNameOrHomeserverUrl(serverNameOrUrl: homeserver.absoluteString)
    let client = try await build(
      builder, storeDirectory: storeDirectory, sessionStore: sessionStore,
      lockHolderName: lockHolderName)
    let handler = try await client.startSsoLogin(
      redirectUrl: redirectURL.absoluteString, idpId: identityProviderId)
    return PendingSSOLogin(client: client, handler: handler)
  }

  /// Finishes `pending` with the web session's callback URL (it reads the `loginToken` from it) and returns the
  /// proxy with the SDK session to save.
  static func finishSSO(_ pending: PendingSSOLogin, callbackURL: URL) async throws -> (
    ClientProxy, Session
  ) {
    try await pending.handler.finish(callbackUrl: callbackURL.absoluteString)
    return (ClientProxy(client: pending.client), try pending.client.session())
  }

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

  /// Cancels and releases objects kept with `keepWhileSyncing` before sync stops, while the client is alive (a room's
  /// timeline when its screen closes). Does nothing when they are no longer kept.
  func release(_ objects: SyncBoundObjects) async {
    await sync.release(objects.id)
  }

  /// Stops the running sync service without releasing what it feeds, for the app in the background. Does nothing when
  /// sync is not running.
  func pauseSync() async {
    await sync.pause()
  }

  /// Empties the SDK's caches (events and media; never the keys or the session). The SDK stops the running sync
  /// service first and starts it again after.
  func clearCaches() async throws {
    try await client.clearCaches(syncService: await sync.current())
  }

  /// Starts the paused sync service again. Does nothing when sync was never started or was stopped for good.
  func resumeSync() async {
    await sync.resume()
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
      // Threads (`m.thread`): the main timeline hides their replies and shows a summary on each root.
      .threadsEnabled(enabled: true, threadSubscriptions: false)
      .crossProcessLockConfig(crossProcessLockConfig: .multiProcess(holderName: lockHolderName))
      .setSessionDelegate(sessionDelegate: delegate)
      .build()
  }
}

/// An SSO sign-in that was started: the client it runs on and the SDK handler that finishes it.
struct PendingSSOLogin: Sendable {
  let client: Client
  let handler: SsoHandler

  /// The URL to open in the web authentication session.
  var url: URL? { URL(string: handler.url()) }
}

/// SDK objects that live only while sync runs: `entries` is cancelled and `objects` released when sync stops.
struct SyncBoundObjects: Sendable {
  let entries: TaskHandle
  let objects: [any Sendable]
  /// Names these objects for `ClientProxy.release(_:)`.
  let id = UUID()
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

  func release(_ id: UUID) {
    guard let index = kept.firstIndex(where: { $0.id == id }) else { return }
    kept.remove(at: index).entries.cancel()
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

  /// The running sync service, if any, for `Client.clearCaches(syncService:)`.
  func current() async -> SyncService? {
    guard let task = running else { return nil }
    return try? await task.value
  }

  /// Stops the SDK sync service but keeps it and what it feeds, so `resume` continues the same room lists and timelines.
  func pause() async {
    guard let task = running, let service = try? await task.value else { return }
    await service.stop()
  }

  func resume() async {
    guard !isClosed, let task = running, let service = try? await task.value else { return }
    await service.start()
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
