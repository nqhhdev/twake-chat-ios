import DesignSystem
import XCTest

final class AccessibilityAuditFlowTests: XCTestCase {
  static let enforced: XCUIAccessibilityAuditType = [
    .sufficientElementDescription, .trait, .elementDetection,
  ]

  override func setUp() { continueAfterFailure = true }

  @MainActor private func audit(_ app: XCUIApplication, _ screen: String) throws {
    try XCTContext.runActivity(named: "Accessibility audit: \(screen)") { _ in
      try app.performAccessibilityAudit(for: Self.enforced)
    }
  }

  @MainActor func testSignedOutScreensPassTheAudit() throws {
    let app = E2EApp.launch()
    let company = app.buttons[A11yIdentifiers.welcome.companyServer]
    XCTAssertTrue(company.waitForExistence(timeout: Self.timeout), "Welcome screen")
    try audit(app, "welcome")
    company.tap()
    let server = app.textFields[A11yIdentifiers.homeserverPicker.server]
    XCTAssertTrue(server.waitForExistence(timeout: Self.timeout), "Homeserver picker")
    try audit(app, "homeserver")
    replaceText(of: server, with: E2EConfig.homeserver)
    app.buttons[A11yIdentifiers.homeserverPicker.continue].tap()
    let username = app.textFields[A11yIdentifiers.passwordLogin.username]
    XCTAssertTrue(username.waitForExistence(timeout: Self.timeout), "Password form")
    try audit(app, "password")
  }

  @MainActor func testSignedInScreensPassTheAudit() throws {
    let app = E2EApp.launch()
    signIn(app)
    XCTAssertTrue(
      chatRow(app, named: "E2E Chat").waitForExistence(timeout: Self.timeout), "Chat list")
    try audit(app, "chatList")
    openRoom(app, named: "E2E Chat")
    try audit(app, "room")
    goBackToChatList(app)
    openSettings(app)
    XCTAssertTrue(
      app.buttons[A11yIdentifiers.settings.logout].waitForExistence(timeout: Self.timeout),
      "Settings")
    try audit(app, "settings")
  }
}
