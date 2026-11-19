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

    // One scroll up, held at the end so inertia is not still moving the list when we pick a
    // message. Watch a row that is actually on screen: the first History static text is the
    // oldest loaded line, often still above the viewport.
    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
    let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
    start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)

    guard let anchor = visibleMessage(app, prefix: "History ") else {
      return XCTFail("A history message after scrolling")
    }
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
