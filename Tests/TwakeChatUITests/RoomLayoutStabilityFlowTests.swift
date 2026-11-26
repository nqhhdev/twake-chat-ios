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
}
