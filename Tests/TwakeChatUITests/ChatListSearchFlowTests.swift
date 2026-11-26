import DesignSystem
import XCTest

final class ChatListSearchFlowTests: XCTestCase {
  override func setUp() { continueAfterFailure = false }

  @MainActor func testChatListFilters() {
    let app = E2EApp.launch()
    signIn(app)
    let chat = app.buttons[A11yIdentifiers.chatList.room("E2E Chat")]
    let history = app.buttons[A11yIdentifiers.chatList.room("E2E History")]
    typeInto(app.searchFields.firstMatch, "E2E ", "Search field")
    XCTAssertTrue(chat.waitForExistence(timeout: Self.timeout), "E2E Chat row")
    XCTAssertTrue(history.waitForExistence(timeout: Self.timeout), "E2E History row")

    tapWhenReady(app.buttons[A11yIdentifiers.chatList.filter("People")], "People chip")
    waitUntilGone(chat, "A group leaves the People filter")
    tapWhenReady(app.buttons[A11yIdentifiers.chatList.filter("Groups")], "Groups chip")
    XCTAssertTrue(chat.waitForExistence(timeout: Self.timeout), "A group is under Groups")
    tapWhenReady(app.buttons[A11yIdentifiers.chatList.filter("All")], "All chip")
    XCTAssertTrue(history.waitForExistence(timeout: Self.timeout), "All chats are back")
  }

  @MainActor func testSearchFindsChatsAndMessages() {
    let app = E2EApp.launch()
    signIn(app)
    let chat = app.buttons[A11yIdentifiers.chatList.room("E2E Chat")]
    let history = app.buttons[A11yIdentifiers.chatList.room("E2E History")]

    let search = app.searchFields.firstMatch
    typeInto(search, "E2E History", "Search field")
    XCTAssertTrue(history.waitForExistence(timeout: Self.timeout), "The matching chat shows")
    waitUntilGone(chat, "Another chat is filtered out")
    search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "History".count))
    search.typeText("Chat")
    XCTAssertTrue(chat.waitForExistence(timeout: Self.timeout), "A new name shows its chat")
    waitUntilGone(history, "The previous match is filtered out")

    search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "E2E Chat".count))
    search.typeText("Hello from Bob")
    let result = app.buttons.matching(
      NSPredicate(
        format: "label CONTAINS %@ AND NOT (identifier BEGINSWITH %@)", "Hello from Bob",
        "chatList.room.")
    ).firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: Self.timeout), "The server finds the message")
    result.tap()
    XCTAssertTrue(
      composer(app).waitForExistence(timeout: Self.timeout), "The result opens its chat")
  }
}
