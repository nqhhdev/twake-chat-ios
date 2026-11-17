import DesignSystem
import XCTest

/// Flow 3: opening a long room loads one page of history and stays at the bottom; scrolling up keeps the reader's
/// place. Known to fail until #80 (back-pagination loops and moves the scroll position) is fixed.
final class PaginationFlowTests: XCTestCase {
  override func setUp() { continueAfterFailure = true }

  @MainActor func testBackPaginationFiresOnceAndKeepsPosition() {
    let app = E2EApp.launch()
    signIn(app)
    openRoom(app, named: "E2E History")
    let latest = message(app, containing: "History 300")
    XCTAssertTrue(latest.waitForExistence(timeout: Self.timeout), "The newest message")

    XCTExpectFailure("#80: back-pagination loops and moves the scroll position", strict: false) {
      // Untouched for a few seconds, the timeline must stay on the newest message.
      sleep(5)
      XCTAssertTrue(latest.isHittable, "Still at the bottom after idling")

      // One scroll up: the message under the finger must still be on screen once the page has loaded.
      app.swipeDown()
      sleep(1)
      let anchor = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "History "))
        .element(boundBy: 0)
      guard anchor.exists else { return XCTFail("No history message on screen after scrolling") }
      let label = anchor.label
      sleep(5)
      XCTAssertTrue(
        message(app, containing: label).exists && message(app, containing: label).isHittable,
        "\(label) stays on screen after one page")
      // Without more scrolling, the oldest message must not have been reached (it would if paging never stops).
      XCTAssertFalse(
        app.staticTexts["History 1"].exists, "Pagination stopped without further scrolling")
    }
  }
}
