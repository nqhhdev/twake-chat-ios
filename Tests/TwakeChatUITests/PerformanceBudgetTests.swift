import DesignSystem
import XCTest

final class PerformanceBudgetTests: XCTestCase {
  override func setUp() { continueAfterFailure = false }

  private static var options: XCTMeasureOptions {
    let options = XCTMeasureOptions()
    options.iterationCount = 5
    return options
  }

  @MainActor func testColdLaunchTime() {
    measure(metrics: [XCTApplicationLaunchMetric()], options: Self.options) {
      let app = XCUIApplication()
      app.launchEnvironment["IS_RUNNING_E2E_TESTS"] = "1"
      app.launchEnvironment["E2E_SKIP_SESSION_PROMPT"] = "1"
      app.launchEnvironment["E2E_HOMESERVER"] = E2EConfig.homeserver
      app.launch()
    }
  }

  @MainActor func testTimelineScrollHitches() {
    let app = E2EApp.launch()
    signIn(app)
    openRoom(app, named: "E2E History")
    let timeline = app.scrollViews.firstMatch
    XCTAssertTrue(timeline.waitForExistence(timeout: Self.timeout), "Timeline")
    let options = Self.options
    options.invocationOptions = [.manuallyStop]
    measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
      timeline.swipeDown(velocity: .fast)
      stopMeasuring()
      timeline.swipeUp(velocity: .fast)
    }
  }

  @MainActor func testChatListScrollHitches() {
    let app = E2EApp.launch()
    signIn(app)
    let list = app.collectionViews.firstMatch
    XCTAssertTrue(list.waitForExistence(timeout: Self.timeout), "Chat list")
    let options = Self.options
    options.invocationOptions = [.manuallyStop]
    measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
      list.swipeUp(velocity: .fast)
      stopMeasuring()
      list.swipeDown(velocity: .fast)
    }
  }
}
