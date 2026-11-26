import XCTest

final class ColdStartFlowTests: XCTestCase {
  static let alias = "ios-cold-start"
  static let pushedBody = "cold start ping"
  static let earlierBody = "before the app was killed"

  @MainActor func testTappingANotificationAfterTheAppWasKilledOpensItsNewRoom() async throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["E2E_PUSHES_COLD_START"] == "1",
      "Needs the push from the host: scripts/e2e.sh cold-start")
    let app = E2EApp.launch()
    signIn(app)
    allowNotifications()
    app.terminate()

    let otherDevice = try await E2ERest.login(user: E2EConfig.user, password: E2EConfig.password)
    let roomName = "Cold start \(UUID().uuidString.prefix(6))"
    try await otherDevice.removeAlias(Self.alias)
    let roomId = try await otherDevice.createRoom(name: roomName, alias: Self.alias)
    try await otherDevice.send(Self.pushedBody, in: roomId)

    tapTheNotificationAndCheckTheRoom(app, named: roomName)

    try? await otherDevice.removeAlias(Self.alias)
    try? await otherDevice.leaveAndForget(roomId)
    try? await otherDevice.logout()
  }

  @MainActor func testTappingANotificationForAChatOpenedBeforeTheAppWasKilledShowsTheNewMessage()
    async throws
  {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["E2E_PUSHES_COLD_START"] == "1",
      "Needs the push from the host: scripts/e2e.sh cold-start")
    let otherDevice = try await E2ERest.login(user: E2EConfig.user, password: E2EConfig.password)
    let roomName = "Known chat \(UUID().uuidString.prefix(6))"
    try await otherDevice.removeAlias(Self.alias)
    let roomId = try await otherDevice.createRoom(name: roomName, alias: Self.alias)
    try await otherDevice.send(Self.earlierBody, in: roomId)

    let app = E2EApp.launch()
    signIn(app)
    dismissPromptsAfterSignIn(app)
    openRoom(app, named: roomName)
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", Self.earlierBody))
        .firstMatch.waitForExistence(timeout: Self.timeout),
      "The chat loaded before the app was killed")
    app.terminate()
    try await otherDevice.send(Self.pushedBody, in: roomId)

    tapTheNotificationAndCheckTheRoom(app, named: roomName)

    try? await otherDevice.removeAlias(Self.alias)
    try? await otherDevice.leaveAndForget(roomId)
    try? await otherDevice.logout()
  }
}

extension ColdStartFlowTests {
  @MainActor func tapTheNotificationAndCheckTheRoom(_ app: XCUIApplication, named roomName: String)
  {
    guard let notification = notification(containing: Self.pushedBody) else {
      print(XCUIApplication(bundleIdentifier: "com.apple.springboard").debugDescription)
      XCTFail("No notification within 120 s")
      return
    }
    notification.tap()

    XCTAssertTrue(app.wait(for: .runningForeground, timeout: Self.timeout))
    let message = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS[c] %@", Self.pushedBody)
    ).firstMatch
    XCTAssertTrue(
      message.waitForExistence(timeout: Self.timeout), "The notified message in its room")
    XCTAssertTrue(app.staticTexts[roomName].exists, "The room's real name in the header")
    XCTAssertFalse(app.staticTexts["Could not open this chat."].exists)
  }

  @MainActor func dismissPromptsAfterSignIn(_ app: XCUIApplication) {
    let notNow = app.buttons["Not Now"]
    if notNow.waitForExistence(timeout: 3) { notNow.tap() }
  }

  @MainActor func allowNotifications() {
    let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
    if allow.waitForExistence(timeout: 15) { allow.tap() }
  }

  @MainActor func notification(containing text: String) -> XCUIElement? {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let matching = springboard.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS[c] %@", text))
    if matching.firstMatch.waitForExistence(timeout: 90) { return matching.firstMatch }
    let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.001))
    top.press(
      forDuration: 0.1,
      thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6)))
    return matching.firstMatch.waitForExistence(timeout: 10) ? matching.firstMatch : nil
  }
}

struct E2ERest: Sendable {
  let token: String

  static func login(user: String, password: String) async throws -> E2ERest {
    let reply = try await call(
      "POST", "login", token: nil,
      [
        "type": "m.login.password", "identifier": ["type": "m.id.user", "user": user],
        "password": password, "initial_device_display_name": "iOS UI test",
      ])
    guard let token = reply["access_token"] as? String else {
      throw URLError(.userAuthenticationRequired)
    }
    return E2ERest(token: token)
  }

  func createRoom(name: String, alias: String) async throws -> String {
    let reply = try await Self.call(
      "POST", "createRoom", token: token,
      ["name": name, "preset": "private_chat", "room_alias_name": alias])
    guard let roomId = reply["room_id"] as? String else { throw URLError(.cannotParseResponse) }
    return roomId
  }

  func removeAlias(_ alias: String) async throws {
    let server = URL(string: E2EConfig.homeserver)?.host() ?? "localhost"
    do {
      _ = try await Self.call(
        "DELETE", "directory/room/%23\(alias):\(server)", token: token, nil)
    } catch URLError.fileDoesNotExist {}
  }

  func send(_ text: String, in roomId: String) async throws {
    _ = try await Self.call(
      "PUT", "rooms/\(roomId)/send/m.room.message/\(UUID().uuidString)", token: token,
      ["msgtype": "m.text", "body": text])
  }

  func leaveAndForget(_ roomId: String) async throws {
    _ = try await Self.call("POST", "rooms/\(roomId)/leave", token: token, [:])
    _ = try await Self.call("POST", "rooms/\(roomId)/forget", token: token, [:])
  }

  func logout() async throws {
    _ = try await Self.call("POST", "logout", token: token, [:])
  }

  private static func call(
    _ method: String, _ path: String, token: String?, _ body: [String: Any]?
  ) async throws -> [String: Any] {
    guard let url = URL(string: "\(E2EConfig.homeserver)/_matrix/client/v3/\(path)") else {
      throw URLError(.badURL)
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    if status == 404 { throw URLError(.fileDoesNotExist) }
    guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
    return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
  }
}
