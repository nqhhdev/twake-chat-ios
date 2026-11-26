import DesignSystem
import XCTest

final class SessionPromptFlowTests: XCTestCase {
  static let promptWait: TimeInterval = 35

  override func setUp() { continueAfterFailure = false }

  @MainActor func testTheSessionPromptLeavesAnOpenChatInPlace() {
    let app = E2EApp.launch(skipsSessionPrompt: false)
    signIn(app)
    dismissSavePassword(app)
    openRoom(app, named: "E2E Chat")

    Thread.sleep(forTimeInterval: Self.promptWait)
    XCTAssertTrue(composer(app).exists, "The chat is still open")
    XCTAssertFalse(app.alerts["Unlock your encrypted messages"].exists)

    app.navigationBars.buttons.firstMatch.tap()
    checkTheBannerWaitsOnTheChatList(app)
  }

  @MainActor func testTheSessionPromptLeavesAnOpenNewChatSheetInPlace() {
    let app = E2EApp.launch(skipsSessionPrompt: false)
    signIn(app)
    dismissSavePassword(app)

    let compose = app.buttons["New chat"].firstMatch
    XCTAssertTrue(compose.waitForExistence(timeout: Self.timeout))
    compose.tap()
    let cancel = app.buttons["Cancel"].firstMatch
    XCTAssertTrue(cancel.waitForExistence(timeout: Self.timeout), "The New chat sheet")

    Thread.sleep(forTimeInterval: Self.promptWait)
    XCTAssertTrue(cancel.exists && cancel.isHittable, "The New chat sheet is still open")
    XCTAssertFalse(app.alerts["Unlock your encrypted messages"].exists)

    cancel.tap()
    checkTheBannerWaitsOnTheChatList(app)
  }

  @MainActor private func dismissSavePassword(_ app: XCUIApplication) {
    let notNow = app.buttons["Not Now"]
    if notNow.waitForExistence(timeout: 3) { notNow.tap() }
  }

  @MainActor private func checkTheBannerWaitsOnTheChatList(_ app: XCUIApplication) {
    let banner = app.descendants(matching: .any)[A11yIdentifiers.chatList.sessionPrompt]
    XCTAssertTrue(
      banner.waitForExistence(timeout: Self.timeout), "The prompt waits on the chat list instead")
    banner.buttons["Later"].tap()
    XCTAssertFalse(banner.waitForExistence(timeout: 2))
  }
}
