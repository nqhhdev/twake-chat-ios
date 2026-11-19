import AppShared
import Domain
import Foundation
import MatrixData
import Testing

/// The notification service extension's path on staging (ADR 0009): signs in, takes the newest message of a joined
/// room, then asks a second client on the same store, under the extension's lock name "nse" (ADR 0007), for that
/// event through the SDK's notification client, as the extension does when a push arrives. Read-only: nothing is
/// sent. Opt-in and local only (ADR 0020); skipped without staging credentials. Messages are never printed.
@Suite(.serialized)
struct NotificationContentIntegrationTests {
  private static let credentials = StagingCredentials.load()

  @Test(
    .enabled(
      if: credentials != nil,
      """
      Skipped: set MATRIX_HOMESERVER, MATRIX_USER and MATRIX_PASSWORD (TEST_RUNNER_MATRIX_… through xcodebuild) \
      or create ~/.factos/secrets/twake-chat-ios-staging.env to run the staging integration test (ADR 0020)
      """),
    .timeLimit(.minutes(3)))
  func theExtensionClientReadsTheNewestMessageOfARoom() async throws {
    let credentials = try #require(Self.credentials)
    let storeDirectory = FileManager.default.temporaryDirectory
      .appending(path: "NotificationIntegration-\(UUID().uuidString)", directoryHint: .isDirectory)
    let accessGroup = try #require(
      Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String)
    let sessionStore = KeychainSessionStore(
      service: "app.twake.ios.chat.tests.notification", accessGroup: accessGroup)
    try sessionStore.delete()
    let app = MatrixAuthenticationRepository(
      storeDirectory: storeDirectory, sessionStore: sessionStore, lockHolderName: "tests")
    let roomList = RoomListProxy(authentication: app)
    try await StagingTurn.run {
      var timeline: TimelineProxy?
      do {
        do {
          _ = try await app.login(
            homeserver: credentials.homeserver, username: credentials.user,
            password: credentials.password)
        } catch AuthenticationError.invalidCredentials {
          try Test.cancel(
            "Skipped: the staging server rejected MATRIX_USER and MATRIX_PASSWORD (ADR 0020)")
        }
        // A joined room with a recent message; stopping the list after 45 s ends the wait with a message.
        var roomId: String?
        let rooms = try await roomList.start()
        let listDeadline = Task {
          try await Task.sleep(for: .seconds(45))
          await roomList.stop()
        }
        for await list in rooms {
          roomId = list.first { !$0.isInvite && $0.lastMessageText != nil }?.id
          if roomId != nil { break }
        }
        listDeadline.cancel()
        let room = try #require(roomId, "step 1: no joined room with a message within 45 s")
        let opened = TimelineProxy(roomId: room, authentication: app)
        timeline = opened
        var eventId: String?
        let items = try await opened.open()
        let timelineDeadline = Task {
          try await Task.sleep(for: .seconds(45))
          await opened.close()
        }
        Task { _ = try? await opened.loadOlder() }
        for await list in items {
          eventId = list.reversed().lazy.compactMap { item -> String? in
            if case .message(let message) = item.kind, case .text = message.body {
              return message.eventId
            }
            return nil
          }.first
          if eventId != nil { break }
        }
        timelineDeadline.cancel()
        let event = try #require(eventId, "step 2: no text message loaded in the room within 45 s")

        // The extension runs while the app is suspended: stop the app side's sync first, as the system would.
        await opened.close()
        await roomList.stop()
        let extensionSide = NotificationContentProxy(
          authentication: MatrixAuthenticationRepository(
            storeDirectory: storeDirectory, sessionStore: sessionStore, lockHolderName: "nse"))
        let started = Date()
        let outcome = await extensionSide.content(roomId: room, eventId: event)
        let shown: NotificationContent? =
          if case .show(let content) = outcome { content } else { nil }
        let content = try #require(
          shown, "step 3: the notification client did not show a loaded text message")
        // The system gives a notification service extension about 30 s.
        #expect(Date().timeIntervalSince(started) < 25, "step 3 took too long for an extension")
        #expect(!content.title.isEmpty)
        #expect(!content.body.isEmpty)
      } catch {
        await timeline?.close()
        await roomList.stop()
        try? await app.logout()
        throw error
      }
      try await app.logout()
    }
  }
}
