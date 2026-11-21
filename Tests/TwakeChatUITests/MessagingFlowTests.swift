import DesignSystem
import XCTest

/// Flow 4: send, reply, edit, react and delete a text message in the seeded unencrypted room "E2E Chat".
final class MessagingFlowTests: XCTestCase {
  override func setUp() { continueAfterFailure = false }

  @MainActor func testSendReplyEditReactDelete() {
    let app = E2EApp.launch()
    signIn(app)
    openRoom(app, named: "E2E Chat")
    XCTAssertTrue(
      message(app, containing: "Hello from Bob").waitForExistence(timeout: Self.timeout))

    let marker = String(UUID().uuidString.prefix(6))
    let original = "e2e \(marker) hello"
    send(app, original)
    XCTAssertTrue(
      message(app, containing: original).waitForExistence(timeout: Self.timeout), "Sent")

    openActions(app, on: original)
    tapAction(app, "Reply")
    let reply = "e2e \(marker) reply"
    send(app, reply)
    XCTAssertTrue(
      message(app, containing: reply).waitForExistence(timeout: Self.timeout), "Replied")

    openActions(app, on: reply)
    tapAction(app, "Edit")
    // The edit puts the message in the composer; the cursor goes to the end before the text is replaced, as a tap
    // may land in the middle of it.
    let field = composer(app)
    let drafted = NSPredicate(format: "value CONTAINS %@", reply)
    wait(for: [expectation(for: drafted, evaluatedWith: field)], timeout: Self.timeout)
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
    let draft = (field.value as? String) ?? reply
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: draft.count + 2))
    field.typeText("\(reply) edited")
    app.buttons[A11yIdentifiers.room.send].tap()
    XCTAssertTrue(
      message(app, containing: "\(reply) edited").waitForExistence(timeout: Self.timeout), "Edited")

    openActions(app, on: original)
    let reaction = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "room.reaction.")
    ).firstMatch
    XCTAssertTrue(reaction.waitForExistence(timeout: Self.timeout), "Quick reaction bar")
    let key = String(reaction.identifier.dropFirst("room.reaction.".count))
    reaction.tap()
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label CONTAINS %@", key)).firstMatch
        .waitForExistence(timeout: Self.timeout), "Reaction chip \(key)")

    openActions(app, on: "\(reply) edited")
    tapAction(app, "Delete")
    let gone = NSPredicate(format: "exists == false")
    let deleted = expectation(for: gone, evaluatedWith: message(app, containing: "\(reply) edited"))
    wait(for: [deleted], timeout: Self.timeout)
  }

  @MainActor private func send(_ app: XCUIApplication, _ text: String) {
    let field = composer(app)
    field.tap()
    field.typeText(text)
    app.buttons[A11yIdentifiers.room.send].tap()
  }

  @MainActor private func tapAction(_ app: XCUIApplication, _ title: String) {
    let action = app.buttons[A11yIdentifiers.room.action(title)]
    XCTAssertTrue(action.waitForExistence(timeout: Self.timeout), "Action \(title)")
    action.tap()
  }
}
