import AppShared
import Domain
import Foundation
import MatrixData
import Testing

/// Signs in to staging, starts the room list and waits for a first non-empty list of joined rooms, then stops it and
/// logs out. Opt-in and local only (ADR 0020); skipped without staging credentials (see `StagingCredentials`). Room
/// names and messages are never printed.
@Suite(.serialized)
struct RoomListIntegrationTests {
  private static let credentials = StagingCredentials.load()

  @Test(
    .enabled(
      if: credentials != nil,
      """
      Skipped: set MATRIX_HOMESERVER, MATRIX_USER and MATRIX_PASSWORD (TEST_RUNNER_MATRIX_… through xcodebuild) \
      or create ~/.factos/secrets/twake-chat-ios-staging.env to run the staging integration test (ADR 0020)
      """),
    .timeLimit(.minutes(2)))
  func signedInUserReceivesANonEmptyRoomList() async throws {
    let credentials = try #require(Self.credentials)
    let storeDirectory = FileManager.default.temporaryDirectory
      .appending(path: "RoomListIntegration-\(UUID().uuidString)", directoryHint: .isDirectory)
    let accessGroup = try #require(
      Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String)
    let sessionStore = KeychainSessionStore(
      service: "app.twake.ios.chat.tests.room-list", accessGroup: accessGroup)
    try sessionStore.delete()
    let repository = MatrixAuthenticationRepository(
      storeDirectory: storeDirectory, sessionStore: sessionStore, lockHolderName: "tests")
    let roomList = RoomListProxy(authentication: repository)
    try await StagingTurn.run {
      do {
        do {
          _ = try await repository.login(
            homeserver: credentials.homeserver, username: credentials.user,
            password: credentials.password)
        } catch AuthenticationError.invalidCredentials {
          try Test.cancel(
            "Skipped: the staging server rejected MATRIX_USER and MATRIX_PASSWORD; check the stgtestN account (ADR 0020)"
          )
        }

        let rooms = try await roomList.start()
        // Stopping the room list ends its stream, so a list that stays empty fails with a message, not the time limit.
        let deadline = Task {
          try await Task.sleep(for: .seconds(60))
          await roomList.stop()
        }
        var firstNonEmpty: [RoomSummary]?
        for await list in rooms where !list.isEmpty {
          firstNonEmpty = list
          break
        }
        deadline.cancel()
        await roomList.stop()
        let received = try #require(
          firstNonEmpty,
          "no joined room arrived within 60 s: does MATRIX_USER have joined rooms, and is staging syncing?")
        #expect(received.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty })
        #expect(Set(received.map(\.id)).count == received.count)
      } catch {
        // A failed or skipped run must not leave a session behind: sign out, awaited here.
        await roomList.stop()
        try? await repository.logout()
        throw error
      }
      try await repository.logout()
    }
  }
}
