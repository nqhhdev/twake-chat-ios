import XCTest

final class RoomLayoutStabilityFlowTests: XCTestCase {
  override func setUp() { continueAfterFailure = false }

  @MainActor func testOpeningAChatKeepsTheMessagesInPlace() {
    let app = E2EApp.launch()
    signIn(app)
    for attempt in 1...2 {
      chatRow(app, named: "E2E History").tap()
      let newest = message(app, containing: "History 300")
      XCTAssertTrue(
        newest.waitForExistence(timeout: Self.timeout), "Newest message, opening \(attempt)")
      let samples = sampledFrames(of: newest, for: 2)
      XCTAssertFalse(
        samples.contains(nil),
        "Opening \(attempt): the newest message disappeared after it first showed")
      let frames = samples.compactMap { $0 }
      let settled = frames.last ?? .zero
      let moved = frames.filter {
        abs($0.minX - settled.minX) > 0.5 || abs($0.width - settled.width) > 0.5
      }
      XCTAssertTrue(
        moved.isEmpty,
        "Opening \(attempt): the newest message moved sideways before settling at \(settled): \(moved)"
      )
      goBackToChatList(app)
    }
  }

  @MainActor private func sampledFrames(of element: XCUIElement, for seconds: TimeInterval)
    -> [CGRect?]
  {
    var frames: [CGRect?] = []
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
      frames.append(element.exists ? element.frame : nil)
    }
    return frames
  }

  @MainActor func testTheTimelineKeepsItsInsets() throws {
    let app = E2EApp.launch()
    signIn(app)
    chatRow(app, named: "E2E Layout").tap()
    let newest = message(app, containing: "et la chute de mes tokens")
    XCTAssertTrue(newest.waitForExistence(timeout: Self.timeout), "Newest message")
    checkInsets(app, "on open")
    pauseForScreenshot(1)
    app.swipeDown()
    app.swipeDown()
    checkInsets(app, "after paging up")
    pauseForScreenshot(2)
    app.swipeUp()
    app.swipeUp()
    app.swipeUp()
    let matches = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "I'll let you guess which one I prefer"))
    let quote = (0..<matches.count).map { matches.element(boundBy: $0) }
      .filter { $0.exists && $0.isHittable }
      .max { $0.frame.minY < $1.frame.minY }
    if let quote {
      quote.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.3)).tap()
      Thread.sleep(forTimeInterval: 1.5)
    }
    checkInsets(app, "after a jump")
    pauseForScreenshot(3)
  }

  @MainActor private func checkInsets(_ app: XCUIApplication, _ when: String) {
    let screen = app.windows.firstMatch.frame
    let today = app.staticTexts["Today"].firstMatch
    if today.exists, today.isHittable {
      XCTAssertEqual(
        today.frame.midX, screen.midX, accuracy: 1.5, "Today is centred \(when)")
    }
    let texts = app.staticTexts.matching(
      NSPredicate(
        format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Layout filler", "et la chute"))
    for index in 0..<min(texts.count, 12) {
      let text = texts.element(boundBy: index)
      guard text.exists, text.isHittable else { continue }
      XCTAssertGreaterThanOrEqual(
        text.frame.minX, screen.minX + 12, "\(text.label) starts inside the gutter \(when)")
      XCTAssertLessThanOrEqual(
        text.frame.maxX, screen.maxX - 12, "\(text.label) ends inside the gutter \(when)")
    }
  }

  @MainActor private func pauseForScreenshot(_ number: Int) {
    guard ProcessInfo.processInfo.environment["E2E_SHOTS_PAUSE"] == "1" else { return }
    print("SHOT-NOW-\(number)")
    Thread.sleep(forTimeInterval: 4)
  }
}
