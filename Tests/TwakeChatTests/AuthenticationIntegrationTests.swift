import AppShared
import Domain
import Foundation
import MatrixData
import Testing

/// Staging credentials for the opt-in integration test (ADR 0020). Read from the environment (`MATRIX_HOMESERVER`,
/// `MATRIX_USER`, `MATRIX_PASSWORD`; xcodebuild passes them as `TEST_RUNNER_MATRIX_…`), or else from
/// `~/.factos/secrets/twake-chat-ios-staging.env` in the host's home folder. The values are never printed.
struct StagingCredentials {
  let homeserver: URL
  let user: String
  let password: String

  static let envFile = ".factos/secrets/twake-chat-ios-staging.env"

  static func load() -> StagingCredentials? {
    let environment = ProcessInfo.processInfo.environment
    var values = fileValues(environment: environment)
    // xcodebuild strips the `TEST_RUNNER_` prefix before the test sees the variable; accept both spellings anyway.
    for key in ["MATRIX_HOMESERVER", "MATRIX_USER", "MATRIX_PASSWORD"] {
      for name in ["TEST_RUNNER_\(key)", key] {
        if let value = environment[name], !value.isEmpty { values[key] = value }
      }
    }
    guard let homeserver = values["MATRIX_HOMESERVER"].flatMap(URL.init(string:)),
      let user = values["MATRIX_USER"], !user.isEmpty,
      let password = values["MATRIX_PASSWORD"], !password.isEmpty
    else { return nil }
    return StagingCredentials(homeserver: homeserver, user: user, password: password)
  }

  /// `KEY=value` lines of the env file; `export`, blank lines, comments and quotes are allowed.
  private static func fileValues(environment: [String: String]) -> [String: String] {
    // In the simulator `HOME` is the simulated device's home; the host's is in SIMULATOR_HOST_HOME.
    guard let home = environment["SIMULATOR_HOST_HOME"] ?? environment["HOME"],
      let text = try? String(
        contentsOf: URL(filePath: home).appending(path: envFile), encoding: .utf8)
    else { return [:] }
    var values: [String: String] = [:]
    for line in text.split(whereSeparator: \.isNewline) {
      var entry = line.trimmingCharacters(in: .whitespaces)
      if entry.hasPrefix("#") { continue }
      if entry.hasPrefix("export ") { entry = String(entry.dropFirst("export ".count)) }
      guard let equals = entry.firstIndex(of: "=") else { continue }
      let key = entry[..<equals].trimmingCharacters(in: .whitespaces)
      let value = entry[entry.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
      values[key] = value
    }
    return values
  }
}

/// Logs in to staging, restores the saved session in a fresh client on the same store, then logs out and checks that
/// the store directory and the Keychain item are gone. Opt-in and local only (ADR 0020).
@Suite(.serialized)
struct AuthenticationIntegrationTests {
  private static let credentials = StagingCredentials.load()

  @Test(
    .enabled(
      if: credentials != nil,
      """
      Skipped: set MATRIX_HOMESERVER, MATRIX_USER and MATRIX_PASSWORD (TEST_RUNNER_MATRIX_… through xcodebuild) \
      or create ~/.factos/secrets/twake-chat-ios-staging.env to run the staging integration test (ADR 0020)
      """),
    .timeLimit(.minutes(2)))
  func loginRestoreLogout() async throws {
    let credentials = try #require(Self.credentials)
    let storeDirectory = FileManager.default.temporaryDirectory
      .appending(path: "MatrixDataIntegration-\(UUID().uuidString)", directoryHint: .isDirectory)
    let sessionStore = KeychainSessionStore(
      service: "app.twake.ios.chat.tests.matrix-authentication", accessGroup: try Self.accessGroup)
    try sessionStore.delete()
    let repository = MatrixAuthenticationRepository(
      storeDirectory: storeDirectory, sessionStore: sessionStore, lockHolderName: "tests")
    do {
      try await Self.loginRestoreLogout(
        credentials: credentials, repository: repository, storeDirectory: storeDirectory,
        sessionStore: sessionStore)
    } catch {
      // A failed or skipped run must not leave a session behind: sign out on the saved session, awaited here.
      let cleanup = MatrixAuthenticationRepository(
        storeDirectory: storeDirectory, sessionStore: sessionStore, lockHolderName: "tests-cleanup")
      try? await cleanup.logout()
      throw error
    }
  }

  private static func loginRestoreLogout(
    credentials: StagingCredentials, repository: MatrixAuthenticationRepository, storeDirectory: URL,
    sessionStore: KeychainSessionStore
  ) async throws {
    let session: UserSession
    do {
      session = try await repository.login(
        homeserver: credentials.homeserver, username: credentials.user, password: credentials.password)
    } catch .invalidCredentials {
      // ADR 0020 and the owner's decision of 2026-11-12: a rejected account skips the test, it does not fail it.
      try Test.cancel(
        "Skipped: the staging server rejected MATRIX_USER and MATRIX_PASSWORD; check the stgtestN account (ADR 0020)")
    }
    #expect(session.userId.hasPrefix("@"))
    #expect(isNonEmptyDirectory(storeDirectory))
    #expect(try sessionStore.load()?.userId == session.userId)

    let restoring = MatrixAuthenticationRepository(
      storeDirectory: storeDirectory, sessionStore: sessionStore, lockHolderName: "tests-restore")
    let restored = try #require(try await restoring.restoreSession())
    #expect(restored == session)
    let proxy = try #require(await restoring.clientProxy)
    #expect(try proxy.userId == session.userId)
    #expect(try proxy.deviceId == session.deviceId)

    try await restoring.logout()
    #expect(!FileManager.default.fileExists(atPath: storeDirectory.path(percentEncoded: false)))
    #expect(try sessionStore.load() == nil)
  }

  /// The app's real Keychain group, from the host app's Info.plist. This test runs hosted in `TwakeChatTests` because
  /// the unhosted `MatrixDataTests` bundle has no Keychain entitlement at all (every call fails with -34018).
  private static var accessGroup: String {
    get throws {
      try #require(Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String)
    }
  }

  private static func isNonEmptyDirectory(_ url: URL) -> Bool {
    let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))
    return !(contents ?? []).isEmpty
  }
}
