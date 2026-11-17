import DesignSystem
import XCTest

/// Flow 10: Settings shows the account's display name (#82).
final class ProfileFlowTests: XCTestCase {
  override func setUp() { continueAfterFailure = false }

  @MainActor func testSettingsShowsDisplayName() {
    let app = E2EApp.launch()
    signIn(app)
    openSettings(app)
    // The profile card is one button-like element, so the name is found among any element type.
    let name = app.descendants(matching: .any)[A11yIdentifiers.settings.displayName].firstMatch
    XCTAssertTrue(name.waitForExistence(timeout: Self.timeout), "Profile card")
    let shown = NSPredicate(format: "label == %@", E2EConfig.displayName)
    let matches = expectation(for: shown, evaluatedWith: name)
    wait(for: [matches], timeout: Self.timeout)
  }
}
