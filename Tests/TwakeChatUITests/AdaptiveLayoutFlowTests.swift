import DesignSystem
import XCTest

final class AdaptiveLayoutFlowTests: XCTestCase {
  override func setUp() { continueAfterFailure = false }

  override func tearDown() async throws {
    await MainActor.run { XCUIDevice.shared.orientation = .portrait }
  }

  @MainActor func testTheChatListSitsBesideTheChatFrom905PointsInBothOrientations() throws {
    try XCTSkipUnless(
      UIDevice.current.userInterfaceIdiom == .pad, "The layout of ADR 0022 is checked on an iPad")
    XCUIDevice.shared.orientation = .portrait
    let app = E2EApp.launch()
    signIn(app)
    openRoom(app, named: "E2E Chat")
    let later = app.buttons["Later"]
    if later.waitForExistence(timeout: 5) { later.tap() }
    for orientation in [UIDeviceOrientation.portrait, .landscapeLeft, .portrait] {
      rotate(app, to: orientation)
      if later.exists { later.tap() }
      let field = composer(app)
      XCTAssertTrue(field.waitForExistence(timeout: Self.timeout), "Composer in \(orientation)")
      let width = app.windows.firstMatch.frame.width
      attach(app, named: "\(orientation.rawValue)-\(Int(width))pt")
      let list = app.descendants(matching: .any)[A11yIdentifiers.chatList.list].firstMatch
      if width >= 905 {
        XCTAssertTrue(list.isHittable, "List beside the chat at \(Int(width)) pt")
        XCTAssertTrue(
          (472...width - 320).contains(field.frame.minX),
          "Chat column after the 472 pt list (and the tab sidebar where iOS shows one) at \(Int(width)) pt, composer at \(field.frame.minX)"
        )
        XCTAssertLessThanOrEqual(list.frame.minX, field.frame.minX - 472, "List left of the chat")
      } else {
        XCTAssertFalse(list.isHittable, "One column at \(Int(width)) pt")
        XCTAssertLessThan(field.frame.minX, 120, "Chat full width at \(Int(width)) pt")
      }
    }
  }

  @MainActor private func rotate(_ app: XCUIApplication, to orientation: UIDeviceOrientation) {
    XCUIDevice.shared.orientation = orientation
    let window = app.windows.firstMatch
    let settled = NSPredicate { _, _ in
      let frame = window.frame
      return orientation.isLandscape ? frame.width > frame.height : frame.height > frame.width
    }
    wait(for: [expectation(for: settled, evaluatedWith: nil)], timeout: Self.timeout)
    Thread.sleep(forTimeInterval: 1.5)
  }

  @MainActor private func attach(_ app: XCUIApplication, named name: String) {
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }
}
