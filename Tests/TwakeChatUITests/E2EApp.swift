import DesignSystem
import XCTest

/// Where the suite signs in. `xcodebuild` passes `TEST_RUNNER_E2E_*` from the shell to this process without the
/// prefix (ADR 0020); `scripts/e2e.sh` sets them. The defaults are the users `scripts/e2e.sh up` seeds.
enum E2EConfig {
  private static let environment = ProcessInfo.processInfo.environment
  static var homeserver: String { environment["E2E_HOMESERVER"] ?? "http://localhost:8008" }
  static var user: String { environment["E2E_USER"] ?? "ios-alice" }
  static var password: String { environment["E2E_PASSWORD"] ?? "password" }
  static var peer: String { environment["E2E_PEER"] ?? "ios-bob" }
  static var displayName: String { environment["E2E_DISPLAY_NAME"] ?? "Alice E2E" }
}

/// Launches the app signed out on the E2E homeserver (element-x-ios `Application.launch()` pattern).
enum E2EApp {
  @MainActor static func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["IS_RUNNING_E2E_TESTS"] = "1"
    app.launchEnvironment["E2E_RESET_SESSION"] = "1"
    app.launchEnvironment["E2E_HOMESERVER"] = E2EConfig.homeserver
    app.launch()
    return app
  }
}

extension XCTestCase {
  /// The default wait of the suite: a local homeserver answers fast, sliding sync takes a few seconds.
  static let timeout: TimeInterval = 30

  /// Dismisses the notification permission alert, which iOS shows from SpringBoard after sign-in.
  @MainActor func dismissSystemAlerts() {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    for title in ["Allow", "Don’t Allow", "Don't Allow", "OK"] {
      let button = springboard.alerts.buttons[title]
      if button.exists {
        button.tap()
        return
      }
    }
  }

  /// Welcome → "Use your company server" → homeserver → password form → chat list.
  @MainActor func signIn(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line)
  {
    let company = app.buttons[A11yIdentifiers.welcome.companyServer]
    XCTAssertTrue(
      company.waitForExistence(timeout: Self.timeout), "Welcome screen", file: file, line: line)
    company.tap()

    let server = app.textFields[A11yIdentifiers.homeserverPicker.server]
    XCTAssertTrue(
      server.waitForExistence(timeout: Self.timeout), "Homeserver picker", file: file, line: line)
    replaceText(of: server, with: E2EConfig.homeserver)
    app.buttons[A11yIdentifiers.homeserverPicker.continue].tap()

    let username = app.textFields[A11yIdentifiers.passwordLogin.username]
    XCTAssertTrue(
      username.waitForExistence(timeout: Self.timeout),
      "Password form (the server must offer no SSO; scripts/e2e.sh strips OIDC)", file: file,
      line: line)
    username.tap()
    username.typeText(E2EConfig.user)
    let password = app.secureTextFields[A11yIdentifiers.passwordLogin.password]
    password.tap()
    password.typeText(E2EConfig.password)
    app.buttons[A11yIdentifiers.passwordLogin.signIn].tap()

    let chats =
      app.tabBars.buttons["Chats"].exists
      ? app.tabBars.buttons["Chats"]
      : app.buttons.matching(identifier: "Chats").firstMatch
    XCTAssertTrue(
      chats.waitForExistence(timeout: Self.timeout), "Signed in", file: file, line: line)
    dismissSystemAlerts()
  }

  @MainActor func openSettings(_ app: XCUIApplication) {
    dismissSystemAlerts()
    let tab =
      app.tabBars.buttons["Settings"].exists
      ? app.tabBars.buttons["Settings"]
      // iPad (.sidebarAdaptable) shows Settings in both the tab bar and the sidebar.
      : app.buttons.matching(identifier: "Settings").firstMatch
    XCTAssertTrue(tab.waitForExistence(timeout: Self.timeout))
    tab.tap()
  }

  @MainActor func signOut(
    _ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
  ) {
    openSettings(app)
    let logout = app.buttons[A11yIdentifiers.settings.logout]
    XCTAssertTrue(
      logout.waitForExistence(timeout: Self.timeout), "Logout row", file: file, line: line)
    for _ in 0..<6 where !logout.isHittable { app.swipeUp() }
    logout.tap()
    let confirm = app.buttons[A11yIdentifiers.settings.confirmLogout].firstMatch
    XCTAssertTrue(
      confirm.waitForExistence(timeout: Self.timeout), "Logout confirmation", file: file, line: line
    )
    confirm.tap()
    XCTAssertTrue(
      app.buttons[A11yIdentifiers.welcome.companyServer].waitForExistence(timeout: Self.timeout),
      "Back on the welcome screen", file: file, line: line)
  }

  @MainActor func openRoom(_ app: XCUIApplication, named name: String) {
    let row = app.buttons[A11yIdentifiers.chatList.room(name)]
    XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "Room \(name) in the chat list")
    row.tap()
    XCTAssertTrue(
      app.textViews[A11yIdentifiers.room.composer].waitForExistence(timeout: Self.timeout)
        || app.textFields[A11yIdentifiers.room.composer].waitForExistence(timeout: 1),
      "Composer of \(name)")
  }

  @MainActor func composer(_ app: XCUIApplication) -> XCUIElement {
    let view = app.textViews[A11yIdentifiers.room.composer]
    return view.exists ? view : app.textFields[A11yIdentifiers.room.composer]
  }

  @MainActor func replaceText(of field: XCUIElement, with text: String) {
    field.tap()
    let current = (field.value as? String) ?? ""
    if current == text { return }
    if !current.isEmpty, current != field.placeholderValue {
      field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
    }
    field.typeText(text)
  }

  /// The message whose text contains `text`.
  @MainActor func message(_ app: XCUIApplication, containing text: String) -> XCUIElement {
    app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
  }

  /// The first on-screen message whose label starts with `prefix`.
  /// `isHittable` is not a valid XCUIElementQuery key, so the query is walked.
  @MainActor func visibleMessage(
    _ app: XCUIApplication, prefix: String, timeout: TimeInterval = timeout
  ) -> XCUIElement? {
    let query = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
    let found = expectation(
      for: NSPredicate { _, _ in
        (0..<query.count).contains { query.element(boundBy: $0).isHittable }
      }, evaluatedWith: nil)
    guard XCTWaiter.wait(for: [found], timeout: timeout) == .completed else { return nil }
    return (0..<query.count).map { query.element(boundBy: $0) }.first { $0.isHittable }
  }

  /// Long-presses a message to open its actions layer.
  @MainActor func openActions(_ app: XCUIApplication, on text: String) {
    let bubble = message(app, containing: text)
    XCTAssertTrue(bubble.waitForExistence(timeout: Self.timeout), "Message \(text)")
    bubble.press(forDuration: 0.8)
  }
}
