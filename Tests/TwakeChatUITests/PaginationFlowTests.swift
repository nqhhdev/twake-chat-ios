import DesignSystem
import XCTest

/// Flow 3: opening a long room loads one page of history and stays at the bottom; scrolling up
/// keeps the reader's place.
final class PaginationFlowTests: XCTestCase {
  override func setUp() { continueAfterFailure = true }

  @MainActor func testBackPaginationFiresOnceAndKeepsPosition() {
    let app = E2EApp.launch()
    signIn(app)
    openRoom(app, named: "E2E History")
    let latest = message(app, containing: "History 300")
    XCTAssertTrue(latest.waitForExistence(timeout: Self.timeout), "The newest message")

    // The timeline must not auto-page while the user stays at the bottom: the waiter times out
    // instead of seeing "History 300" leave the screen during this idle window.
    let leftBottom = expectation(
      for: NSPredicate(format: "isHittable == false"), evaluatedWith: latest)
    XCTAssertEqual(
      XCTWaiter.wait(for: [leftBottom], timeout: 5),
      .timedOut,
      "Still at the bottom after idling")

    // One scroll up: the message under the finger must still be on screen once the page has loaded.
    app.swipeDown()
    let history = NSPredicate(format: "label BEGINSWITH %@", "History ")
    let anchor = app.staticTexts.matching(history).element(boundBy: 0)
    XCTAssertTrue(
      anchor.waitForExistence(timeout: Self.timeout), "A history message after scrolling")
    let label = anchor.label
    let leftAnchor = expectation(
      for: NSPredicate(format: "isHittable == false"),
      evaluatedWith: message(app, containing: label))
    XCTAssertEqual(
      XCTWaiter.wait(for: [leftAnchor], timeout: 5),
      .timedOut,
      "\(label) stays on screen after one page")
    // Without more scrolling, the oldest message must not have been reached (it would if paging
    // never stops).
    XCTAssertFalse(
      app.staticTexts["History 1"].exists, "Pagination stopped without further scrolling")
  }
}
