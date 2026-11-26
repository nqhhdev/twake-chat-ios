import AppShared
import Domain
import Foundation
import MatrixData
import Testing

/// `MatrixAuthenticationRepository` without a homeserver (TWAK-64). Hosted, because the Keychain needs the app's
/// entitlements; a test-only service and a temporary store directory keep it off a real session. The unreachable
/// server is a closed local port, so nothing leaves the machine.
@Suite(.serialized)
struct MatrixAuthenticationRepositoryTests {
  private static let unreachable = URL(string: "http://127.0.0.1:9")!
  private let sessionStore: KeychainSessionStore
  private let storeDirectory: URL

  init() throws {
    let group = try #require(
      Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String)
    sessionStore = KeychainSessionStore(
      service: "app.twake.ios.chat.tests.matrix-authentication-repository", accessGroup: group)
    try sessionStore.delete()
    storeDirectory = FileManager.default.temporaryDirectory
      .appending(
        path: "MatrixAuthenticationRepositoryTests-\(UUID().uuidString)",
        directoryHint: .isDirectory)
  }

  private func repository() -> MatrixAuthenticationRepository {
    MatrixAuthenticationRepository(
      storeDirectory: storeDirectory, sessionStore: sessionStore, lockHolderName: "tests")
  }

  private func savedSession(slidingSyncVersion: String? = "native") -> StoredSession {
    StoredSession(
      userId: "@alice:example.org", deviceId: "DEVICE", homeserverURL: Self.unreachable,
      accessToken: "access-token", refreshToken: "refresh-token",
      slidingSyncVersion: slidingSyncVersion)
  }

  private func cleanUp() {
    try? sessionStore.delete()
    try? FileManager.default.removeItem(at: storeDirectory)
  }

  private var storeDirectoryExists: Bool {
    FileManager.default.fileExists(atPath: storeDirectory.path(percentEncoded: false))
  }

  @Test func restoreWithNothingSavedReturnsNilAndNoClient() async throws {
    defer { cleanUp() }
    let repository = repository()
    #expect(try await repository.restoreSession() == nil)
    #expect(await repository.clientProxy == nil)
  }

  /// The Keychain keeps the sliding sync version the repository saves, so a restore can use it.
  @Test(arguments: ["native", "none"])
  func keychainKeepsTheSlidingSyncVersion(version: String) throws {
    defer { cleanUp() }
    let saved = savedSession(slidingSyncVersion: version)
    try sessionStore.save(saved)
    #expect(try sessionStore.load()?.slidingSyncVersion == version)
  }

  /// Logout after a cold launch (no client yet) whose server cannot be reached: it reports `serverUnreachable` and
  /// still clears the store and the Keychain item.
  @Test(.timeLimit(.minutes(1)))
  func logoutWithoutAClientAndNoServerStillDeletesTheStoreAndTheKeychainItem() async throws {
    defer { cleanUp() }
    try FileManager.default.createDirectory(
      at: storeDirectory.appending(path: "data"), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: storeDirectory.appending(path: "data/file"))
    try sessionStore.save(savedSession())

    await #expect(throws: AuthenticationError.serverUnreachable) {
      try await repository().logout()
    }

    #expect(!storeDirectoryExists)
    #expect(try sessionStore.load() == nil)
  }

  /// The SDK store holds one session: a sign-in while one is saved is refused before any network call, and the saved
  /// session and the store are left alone.
  @Test func loginWhileASessionIsSavedIsRefusedAndKeepsIt() async throws {
    defer { cleanUp() }
    let saved = savedSession()
    try sessionStore.save(saved)
    try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    let repository = repository()

    await #expect(throws: AuthenticationError.unknown) {
      _ = try await repository.login(
        homeserver: Self.unreachable, username: "bob", password: "password")
    }

    #expect(try sessionStore.load() == saved)
    #expect(storeDirectoryExists)
    #expect(await repository.clientProxy == nil)
  }

  @Test func logoutWithNothingToDeleteDoesNotThrow() async throws {
    defer { cleanUp() }
    try await repository().logout()
    #expect(!storeDirectoryExists)
  }

  /// A server that cannot be reached is reported as `serverUnreachable`, nothing is saved and no client is kept.
  @Test(.timeLimit(.minutes(1)))
  func loginToAnUnreachableServerReportsServerUnreachable() async throws {
    defer { cleanUp() }
    let repository = repository()
    await #expect(throws: AuthenticationError.serverUnreachable) {
      _ = try await repository.login(
        homeserver: Self.unreachable, username: "alice", password: "password")
    }
    #expect(try sessionStore.load() == nil)
    #expect(await repository.clientProxy == nil)
  }

  /// A restore that fails because the server cannot be reached reports `serverUnreachable` and must not lose the
  /// saved session: the next launch can try again.
  @Test(.timeLimit(.minutes(1)))
  func aRestoreThatCannotReachTheServerReportsItAndKeepsTheSavedSession() async throws {
    defer { cleanUp() }
    let saved = savedSession()
    try sessionStore.save(saved)
    let repository = repository()
    await #expect(throws: AuthenticationError.serverUnreachable) {
      _ = try await repository.restoreSession()
    }
    #expect(await repository.clientProxy == nil)
    #expect(try sessionStore.load() == saved)
  }

  /// Restore against a local fake homeserver: a fresh client on the saved session reports its user and device.
  @Test(.timeLimit(.minutes(1)))
  func restoreBuildsAClientForTheSavedSession() async throws {
    defer { cleanUp() }
    let server = try FakeHomeserver()
    defer { server.stop() }
    let homeserver = server.url
    let saved = StoredSession(
      userId: "@alice:example.org", deviceId: "DEVICE", homeserverURL: homeserver,
      accessToken: "access-token", refreshToken: nil, slidingSyncVersion: "native")
    try sessionStore.save(saved)
    let repository = repository()

    let restored = try #require(try await repository.restoreSession())

    #expect(restored.userId == saved.userId)
    #expect(restored.deviceId == saved.deviceId)
    let proxy = try #require(await repository.clientProxy)
    #expect(try proxy.userId == saved.userId)
    #expect(try proxy.deviceId == saved.deviceId)
  }

  /// Logout whose server call fails: the store directory and the Keychain item are still deleted, and the failure is
  /// reported afterwards (card TWAK-64, ADR 0007). The fake homeserver answers `/versions` and rejects `/logout`.
  @Test(.timeLimit(.minutes(1)))
  func logoutWhenTheServerCallFailsStillDeletesLocallyAndReportsTheError() async throws {
    defer { cleanUp() }
    let server = try FakeHomeserver()
    defer { server.stop() }
    let homeserver = server.url
    try sessionStore.save(
      StoredSession(
        userId: "@alice:example.org", deviceId: "DEVICE", homeserverURL: homeserver,
        accessToken: "access-token", refreshToken: nil, slidingSyncVersion: "native"))
    let repository = repository()
    _ = try #require(try await repository.restoreSession())
    #expect(storeDirectoryExists)

    await #expect(throws: AuthenticationError.self) {
      try await repository.logout()
    }

    #expect(server.requests.contains { $0.hasPrefix("POST ") && $0.hasSuffix("/logout") })
    #expect(!storeDirectoryExists)
    #expect(try sessionStore.load() == nil)
    #expect(await repository.clientProxy == nil)
  }
  /// Logout after a cold launch, with a saved session and no client yet: a client is restored first, so the server is
  /// still asked to sign the device out (`POST …/logout`), and the local state is deleted.
  @Test(.timeLimit(.minutes(1)))
  func logoutAfterAColdLaunchStillCallsTheServer() async throws {
    defer { cleanUp() }
    let server = try FakeHomeserver()
    defer { server.stop() }
    try sessionStore.save(
      StoredSession(
        userId: "@alice:example.org", deviceId: "DEVICE", homeserverURL: server.url,
        accessToken: "access-token", refreshToken: nil, slidingSyncVersion: "native"))

    await #expect(throws: AuthenticationError.self) {
      try await repository().logout()
    }

    #expect(server.requests.contains { $0.hasPrefix("POST ") && $0.hasSuffix("/logout") })
    #expect(!storeDirectoryExists)
    #expect(try sessionStore.load() == nil)
  }

  // MARK: Tester (TWAK-64): login, and logout whose server call succeeds, against the local fake homeserver.

  private static let loginAnswer = (
    status: "200 OK",
    body: """
    {"user_id":"@alice:example.org","access_token":"fixture-access","device_id":"NEWDEVICE",\
    "refresh_token":"fixture-refresh"}
    """
  )
  private static let logoutAnswer = (status: "200 OK", body: "{}")

  /// Card: a plain username and a full `@user:server` are both sent to the server unchanged as the user identifier
  /// (login.dart), and login returns and saves the session, sliding sync version included, and keeps the client.
  @Test(.timeLimit(.minutes(1)))
  func signInAndSignOutAreReportedForTheAccountRegistry() async throws {
    defer { cleanUp() }
    let server = try FakeHomeserver(responses: ["/login": Self.loginAnswer])
    defer { server.stop() }
    let changes = SessionChanges()
    let repository = MatrixAuthenticationRepository(
      storeDirectory: storeDirectory, sessionStore: sessionStore, lockHolderName: "tests",
      onSessionChange: { changes.append($0) })

    _ = try await repository.login(
      homeserver: server.url, username: "alice", password: "fixture-password")
    #expect(changes.all == [.signedIn(userId: "@alice:example.org")])

    try? await repository.logout()
    #expect(
      changes.all == [
        .signedIn(userId: "@alice:example.org"), .signedOut(userId: "@alice:example.org"),
      ])
  }

  @Test(.timeLimit(.minutes(1)))
  func aSignOutWithNothingSavedReportsNothing() async throws {
    defer { cleanUp() }
    let changes = SessionChanges()
    let repository = MatrixAuthenticationRepository(
      storeDirectory: storeDirectory, sessionStore: sessionStore, lockHolderName: "tests",
      onSessionChange: { changes.append($0) })
    try await repository.logout()
    #expect(changes.all.isEmpty)
  }

  @Test(.timeLimit(.minutes(1)), arguments: ["alice", "@alice:example.org"])
  func loginSendsTheUsernameUnchangedAndSavesTheSession(username: String) async throws {
    defer { cleanUp() }
    let server = try FakeHomeserver(responses: ["/login": Self.loginAnswer])
    defer { server.stop() }
    let repository = repository()

    let session = try await repository.login(
      homeserver: server.url, username: username, password: "fixture-password")

    let body = try #require(server.lastBody(ofPathEndingWith: "/login"))
    #expect(body["type"] as? String == "m.login.password")
    let identifier = try #require(body["identifier"] as? [String: Any])
    #expect(identifier["type"] as? String == "m.id.user")
    #expect(identifier["user"] as? String == username)

    #expect(session.userId == "@alice:example.org")
    #expect(session.deviceId == "NEWDEVICE")
    #expect(session.accessToken == "fixture-access")
    #expect(session.refreshToken == "fixture-refresh")
    #expect(session.homeserverURL.host() == server.url.host())
    #expect(session.homeserverURL.port == server.url.port)

    let saved = try #require(try sessionStore.load())
    #expect(saved.userId == session.userId)
    #expect(saved.deviceId == session.deviceId)
    #expect(saved.accessToken == session.accessToken)
    #expect(saved.refreshToken == session.refreshToken)
    #expect(saved.homeserverURL == session.homeserverURL)
    #expect(saved.slidingSyncVersion == "native")
    #expect(storeDirectoryExists)
    let proxy = try #require(await repository.clientProxy)
    #expect(try proxy.userId == "@alice:example.org")
    #expect(try proxy.deviceId == "NEWDEVICE")
  }

  /// The server rejects the password (`403 M_FORBIDDEN`): `invalidCredentials`, nothing saved, no client kept.
  @Test(.timeLimit(.minutes(1)))
  func loginRejectedByTheServerReportsInvalidCredentialsAndSavesNothing() async throws {
    defer { cleanUp() }
    let server = try FakeHomeserver(responses: [
      "/login": (
        status: "403 Forbidden",
        body: #"{"errcode":"M_FORBIDDEN","error":"Invalid username or password"}"#
      )
    ])
    defer { server.stop() }
    let repository = repository()

    await #expect(throws: AuthenticationError.invalidCredentials) {
      _ = try await repository.login(
        homeserver: server.url, username: "alice", password: "wrong-password")
    }

    #expect(server.requests.contains { $0.hasPrefix("POST ") && $0.hasSuffix("/login") })
    #expect(try sessionStore.load() == nil)
    #expect(await repository.clientProxy == nil)
  }

  /// The integration test's flow, offline: log in, restore the saved session in a fresh repository on the same store,
  /// then log out with a server that accepts it. Logout reports no error and deletes the store and the Keychain item.
  @Test(.timeLimit(.minutes(1)))
  func loginThenRestoreInAFreshClientThenLogoutClearsEverything() async throws {
    defer { cleanUp() }
    let server = try FakeHomeserver(responses: [
      "/login": Self.loginAnswer, "/logout": Self.logoutAnswer,
    ])
    defer { server.stop() }

    let session = try await repository().login(
      homeserver: server.url, username: "alice", password: "fixture-password")

    let restoring = MatrixAuthenticationRepository(
      storeDirectory: storeDirectory, sessionStore: sessionStore, lockHolderName: "tests-restore")
    let restored = try #require(try await restoring.restoreSession())
    #expect(restored == session)
    let proxy = try #require(await restoring.clientProxy)
    #expect(try proxy.userId == session.userId)
    #expect(try proxy.deviceId == session.deviceId)

    try await restoring.logout()

    #expect(server.requests.contains { $0.hasPrefix("POST ") && $0.hasSuffix("/logout") })
    #expect(!storeDirectoryExists)
    #expect(try sessionStore.load() == nil)
    #expect(await restoring.clientProxy == nil)
    #expect(try await restoring.restoreSession() == nil)
  }
}

/// A homeserver on the loopback interface for the tests above: `GET …/versions` advertises native sliding sync,
/// `…/logout` fails with `400 M_UNKNOWN`, anything else is `404 M_UNRECOGNIZED`. `responses` replaces the answer for
/// a path suffix (for example `/login`). It records each request line and body.
/// Plain BSD sockets (re-exported by Foundation), one thread per connection; nothing leaves the machine.
/// Internal, not private: the TWAK-65 root lifecycle tests reuse it.
final class FakeHomeserver: @unchecked Sendable {
  let url: URL
  private let listening: Int32
  private let responses: [String: (status: String, body: String)]
  private let lock = NSLock()
  private var recorded: [String] = []
  private var recordedBodies: [(request: String, body: String)] = []
  private var stopped = false

  var requests: [String] { lock.withLock { recorded } }

  /// The JSON body of the last request whose path ends with `suffix`.
  func lastBody(ofPathEndingWith suffix: String) -> [String: Any]? {
    let body = lock.withLock { recordedBodies.last { $0.request.hasSuffix(suffix) }?.body }
    return body.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
  }

  init(responses: [String: (status: String, body: String)] = [:]) throws {
    self.responses = responses
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { throw POSIXError(.EIO) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let bound = withUnsafeMutablePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(fd, $0, length) == 0 && listen(fd, 16) == 0 && getsockname(fd, $0, &length) == 0
      }
    }
    guard bound else {
      close(fd)
      throw POSIXError(.EADDRNOTAVAIL)
    }
    listening = fd
    url = URL(string: "http://127.0.0.1:\(UInt16(bigEndian: address.sin_port))")!
    Thread.detachNewThread { [self] in acceptLoop() }
  }

  func stop() {
    lock.withLock { stopped = true }
  }

  private var isStopped: Bool { lock.withLock { stopped } }

  private func acceptLoop() {
    defer { close(listening) }
    while !isStopped {
      var waiting = pollfd(fd: listening, events: Int16(POLLIN), revents: 0)
      guard poll(&waiting, 1, 100) > 0 else { continue }
      let client = accept(listening, nil, nil)
      guard client >= 0 else { continue }
      var on: Int32 = 1
      setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
      Thread.detachNewThread { [self] in serve(client) }
    }
  }

  private func serve(_ client: Int32) {
    defer { close(client) }
    var buffer = Data()
    var chunk = [UInt8](repeating: 0, count: 65_536)
    while true {
      let count = read(client, &chunk, chunk.count)
      guard count > 0 else { return }
      buffer.append(contentsOf: chunk[0..<count])
      guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { continue }
      let head = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
      let contentLength =
        head.components(separatedBy: "\r\n")
        .first { $0.lowercased().hasPrefix("content-length:") }
        .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) }
        ?? 0
      guard buffer.count - headerEnd.upperBound >= contentLength else { continue }
      let body = String(
        decoding: buffer[headerEnd.upperBound..<(headerEnd.upperBound + contentLength)],
        as: UTF8.self)
      let response = Data(respond(to: head, body: body).utf8)
      _ = response.withUnsafeBytes { write(client, $0.baseAddress, response.count) }
      return
    }
  }

  private func respond(to head: String, body requestBody: String) -> String {
    let requestLine = head.components(separatedBy: "\r\n").first ?? ""
    let parts = requestLine.split(separator: " ")
    let method = parts.first.map(String.init) ?? ""
    let path = parts.count > 1 ? String(parts[1].split(separator: "?").first ?? "") : ""
    lock.withLock {
      recorded.append("\(method) \(path)")
      recordedBodies.append(("\(method) \(path)", requestBody))
    }
    let (status, body): (String, String)
    if method == "GET", path.hasSuffix("/_matrix/client/v3/login") {
      // The homeserver picker reads the login flows first: a password-only server.
      status = "200 OK"
      body = #"{"flows":[{"type":"m.login.password"}]}"#
    } else if let override = responses.first(where: { path.hasSuffix($0.key) })?.value {
      status = override.status
      body = override.body
    } else if path.hasSuffix("/_matrix/client/versions") {
      status = "200 OK"
      body = """
        {"versions":["r0.6.1","v1.1","v1.2","v1.3","v1.4","v1.5","v1.6","v1.7","v1.8","v1.9","v1.10","v1.11"],\
        "unstable_features":{"org.matrix.simplified_msc3575":true}}
        """
    } else if path.hasSuffix("/logout") {
      status = "400 Bad Request"
      body = #"{"errcode":"M_UNKNOWN","error":"Fake homeserver failure"}"#
    } else {
      status = "404 Not Found"
      body = #"{"errcode":"M_UNRECOGNIZED","error":"Unrecognized request"}"#
    }
    return
      "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n"
      + "Connection: close\r\n\r\n\(body)"
  }
}

private final class SessionChanges: @unchecked Sendable {
  private let lock = NSLock()
  private var changes: [SessionChange] = []

  var all: [SessionChange] { lock.withLock { changes } }

  func append(_ change: SessionChange) {
    lock.withLock { changes.append(change) }
  }
}
