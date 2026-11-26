import DesignSystem
import XCTest

/// Flow 1: sign in with a password, see the chat list, log out (element-x-ios `UserFlowTests` shape).
final class AuthenticationFlowTests: XCTestCase {
  override func setUp() { continueAfterFailure = false }

  @MainActor func testSignInChatListAndLogout() {
    let app = E2EApp.launch()
    signIn(app)
    XCTAssertTrue(chatRow(app, named: "E2E Chat").exists, "The seeded room is in the chat list")
    signOut(app)
  }
}
