import DesignSystem
import XCTest

final class NewChatFlowTests: XCTestCase {
  override func setUp() { continueAfterFailure = false }

  @MainActor func testStartADirectChat() {
    let app = E2EApp.launch()
    signIn(app)
    tapWhenReady(app.buttons[A11yIdentifiers.chatList.newChat], "New chat")
    typeInto(app.searchFields.firstMatch, E2EConfig.peerLocalpart, "People search")
    tapWhenReady(app.buttons[A11yIdentifiers.newChat.person(E2EConfig.peerId)], "Peer in results")
    XCTAssertTrue(
      app.navigationBars[E2EConfig.peerDisplayName].waitForExistence(timeout: Self.timeout),
      "The direct chat with the peer opens")
  }

  @MainActor func testCreateAGroup() {
    let app = E2EApp.launch()
    signIn(app)
    let name = "E2E Group \(Self.marker())"
    tapWhenReady(app.buttons[A11yIdentifiers.chatList.newChat], "New chat")
    tapWhenReady(app.buttons["Group"], "Group kind")
    typeInto(app.textFields[A11yIdentifiers.newChat.groupName], name, "Group name")
    typeInto(app.searchFields.firstMatch, E2EConfig.peerLocalpart, "People search")
    tapWhenReady(app.buttons[A11yIdentifiers.newChat.person(E2EConfig.peerId)], "Pick the peer")
    tapWhenReady(app.navigationBars["New chat"].buttons["Close"], "End the people search")
    tapWhenReady(app.buttons[A11yIdentifiers.newChat.create], "Create")
    XCTAssertTrue(composer(app).waitForExistence(timeout: Self.timeout), "The group opens")
    goBackToChatList(app)
    XCTAssertTrue(
      app.buttons[A11yIdentifiers.chatList.room(name)].waitForExistence(timeout: Self.timeout),
      "The group is in the chat list")
  }
}
