import DesignSystem
import XCTest

final class SpacesFoldersFlowTests: XCTestCase {
  override func setUp() { continueAfterFailure = false }

  @MainActor func testCreateASpaceAndASubSpace() {
    let app = E2EApp.launch()
    signIn(app)
    let space = "E2E Space \(Self.marker())"
    let subspace = "\(space) sub"
    tapWhenReady(app.buttons[A11yIdentifiers.chatList.more], "More menu")
    tapWhenReady(app.buttons[A11yIdentifiers.chatList.newSpace], "New Space")
    typeInto(app.textFields[A11yIdentifiers.newSpace.name], space, "Space name")
    tapWhenReady(app.buttons[A11yIdentifiers.newSpace.create], "Create the space")
    XCTAssertTrue(
      app.navigationBars[space].waitForExistence(timeout: Self.timeout), "The space opens")

    tapWhenReady(element(app, A11yIdentifiers.space.add), "Add menu")
    tapWhenReady(app.buttons[A11yIdentifiers.space.newSubspace], "New Sub-space")
    typeInto(app.textFields[A11yIdentifiers.newSpace.name], subspace, "Sub-space name")
    tapWhenReady(app.buttons[A11yIdentifiers.newSpace.create], "Create the sub-space")
    XCTAssertTrue(
      element(app, A11yIdentifiers.space.child(subspace)).waitForExistence(timeout: Self.timeout),
      "The sub-space is listed in its space")
  }

  @MainActor func testCreateUseAndDeleteAFolder() {
    let app = E2EApp.launch()
    signIn(app)
    let folder = "F\(Self.marker())"
    revealChip(app, app.buttons[A11yIdentifiers.chatList.newFolder])
    tapWhenReady(app.buttons[A11yIdentifiers.chatList.newFolder], "New folder chip")
    typeInto(app.textFields[A11yIdentifiers.folderEditor.name], folder, "Folder name")
    tapWhenReady(app.buttons[A11yIdentifiers.folderEditor.save], "Save the folder")
    let chip = app.buttons[A11yIdentifiers.chatList.folder(folder)]
    XCTAssertTrue(chip.waitForExistence(timeout: Self.timeout), "Folder chip")

    chatRow(app, named: "E2E Chat").press(forDuration: 0.8)
    tapWhenReady(app.buttons["Folders"], "Folders in the chat menu")
    tapWhenReady(app.buttons[folder].firstMatch, "Add the chat to the folder")

    let search = app.searchFields.firstMatch
    search.tap()
    search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "E2E Chat".count))
    search.typeText("E2E")
    revealChip(app, chip)
    tapWhenReady(chip, "Folder chip")
    XCTAssertTrue(
      app.buttons[A11yIdentifiers.chatList.room("E2E Chat")].waitForExistence(
        timeout: Self.timeout), "The added chat is in the folder")
    waitUntilGone(
      app.buttons[A11yIdentifiers.chatList.room("E2E History")], "Other chats are not")

    revealChip(app, chip)
    chip.press(forDuration: 0.8)
    tapWhenReady(app.buttons["Delete Folder"], "Delete in the chip menu")
    tapWhenReady(app.buttons["Delete Folder"].firstMatch, "Confirm the deletion")
    waitUntilGone(chip, "The folder is gone")
  }

  @MainActor private func revealChip(_ app: XCUIApplication, _ chip: XCUIElement) {
    let row = app.buttons[A11yIdentifiers.chatList.filter("All")].frame.midY
    let origin = app.coordinate(withNormalizedOffset: .zero)
    let screen = app.windows.firstMatch.frame
    for _ in 0..<4 where !(chip.exists && screen.contains(chip.frame)) {
      origin.withOffset(CGVector(dx: 330, dy: row))
        .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 40, dy: row)))
    }
  }

}
