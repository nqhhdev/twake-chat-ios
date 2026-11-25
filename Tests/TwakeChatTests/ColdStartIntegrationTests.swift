import AppShared
import Domain
import Foundation
import MatrixData
import Testing

@Suite(.serialized)
struct ColdStartIntegrationTests {
  private static let credentials = StagingCredentials.load()

  @Test(
    .enabled(
      if: credentials != nil,
      """
      Skipped: set MATRIX_HOMESERVER, MATRIX_USER and MATRIX_PASSWORD (TEST_RUNNER_MATRIX_… through xcodebuild) \
      or create ~/.factos/secrets/twake-chat-ios-staging.env to run the staging integration test (ADR 0020)
      """),
    .timeLimit(.minutes(3)))
  func aRoomCreatedWhileTheAppWasDeadOpensWithItsMessageOnTheNextLaunch() async throws {
    let credentials = try #require(Self.credentials)
    let storeDirectory = FileManager.default.temporaryDirectory
      .appending(path: "ColdStartIntegration-\(UUID().uuidString)", directoryHint: .isDirectory)
    let accessGroup = try #require(
      Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String)
    let sessionStore = KeychainSessionStore(
      service: "app.twake.ios.chat.tests.cold-start", accessGroup: accessGroup)
    try sessionStore.delete()
    let firstRun = MatrixAuthenticationRepository(
      storeDirectory: storeDirectory, sessionStore: sessionStore, lockHolderName: "tests")
    try await StagingTurn.run {
      let otherDevice = StagingRest(homeserver: credentials.homeserver)
      var roomId: String?
      var nextRun: MatrixAuthenticationRepository?
      var timeline: TimelineProxy?
      do {
        do {
          _ = try await firstRun.login(
            homeserver: credentials.homeserver, username: credentials.user,
            password: credentials.password)
        } catch AuthenticationError.invalidCredentials {
          try Test.cancel(
            "Skipped: the staging server rejected MATRIX_USER and MATRIX_PASSWORD (ADR 0020)")
        }
        let roomList = RoomListProxy(authentication: firstRun)
        let rooms = try await roomList.start()
        let listDeadline = Task {
          try await Task.sleep(for: .seconds(30))
          await roomList.stop()
        }
        for await list in rooms where !list.isEmpty { break }
        listDeadline.cancel()
        await roomList.stop()

        try await otherDevice.login(user: credentials.user, password: credentials.password)
        let created = try await otherDevice.createRoom(
          name: "iOS cold start \(UUID().uuidString.prefix(8))")
        roomId = created
        let ping = "cold start ping \(UUID().uuidString.prefix(8))"
        try await otherDevice.send(ping, in: created)

        let relaunched = MatrixAuthenticationRepository(
          storeDirectory: storeDirectory, sessionStore: sessionStore, lockHolderName: "app")
        nextRun = relaunched
        _ = try await relaunched.restoreSession()
        let opened = TimelineProxy(roomId: created, authentication: relaunched)
        timeline = opened
        let started = ContinuousClock.now
        let items = try await opened.open()
        let deadline = Task {
          try await Task.sleep(for: .seconds(30))
          await opened.close()
        }
        let paging = Task {
          while !Task.isCancelled {
            if (try? await opened.loadOlder()) == true { return }
            try? await Task.sleep(for: .milliseconds(500))
          }
        }
        var shown = false
        for await list in items {
          shown = list.contains { item in
            if case .message(let message) = item.kind, case .text(let body) = message.body {
              return body == ping
            }
            return false
          }
          if shown { break }
        }
        deadline.cancel()
        paging.cancel()
        #expect(shown, "the new room's message did not show within 30 s of the relaunch")
        #expect(ContinuousClock.now - started < .seconds(20))
      } catch {
        await timeline?.close()
        if let roomId { try? await otherDevice.leaveAndForget(roomId) }
        try? await otherDevice.logout()
        if let nextRun { try? await nextRun.logout() } else { try? await firstRun.logout() }
        throw error
      }
      await timeline?.close()
      if let roomId { try? await otherDevice.leaveAndForget(roomId) }
      try? await otherDevice.logout()
      try await (nextRun ?? firstRun).logout()
    }
  }
}

actor StagingRest {
  private let homeserver: URL
  private var token: String?

  init(homeserver: URL) { self.homeserver = homeserver }

  func login(user: String, password: String) async throws {
    let reply = try await call(
      "POST", "login",
      [
        "type": "m.login.password", "identifier": ["type": "m.id.user", "user": user],
        "password": password, "initial_device_display_name": "iOS integration test",
      ])
    token = reply["access_token"] as? String
  }

  func createRoom(name: String) async throws -> String {
    let reply = try await call("POST", "createRoom", ["name": name, "preset": "private_chat"])
    guard let roomId = reply["room_id"] as? String else { throw URLError(.cannotParseResponse) }
    return roomId
  }

  func send(_ text: String, in roomId: String) async throws {
    _ = try await call(
      "PUT", "rooms/\(roomId)/send/m.room.message/\(UUID().uuidString)",
      ["msgtype": "m.text", "body": text])
  }

  func leaveAndForget(_ roomId: String) async throws {
    _ = try await call("POST", "rooms/\(roomId)/leave", [:])
    _ = try await call("POST", "rooms/\(roomId)/forget", [:])
  }

  func logout() async throws {
    guard token != nil else { return }
    _ = try await call("POST", "logout", [:])
    token = nil
  }

  private func call(_ method: String, _ path: String, _ body: [String: Any]) async throws
    -> [String: Any]
  {
    let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    guard let url = URL(string: "_matrix/client/v3/\(encoded)", relativeTo: homeserver) else {
      throw URLError(.badURL)
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status)
    else { throw URLError(.badServerResponse) }
    return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
  }
}
