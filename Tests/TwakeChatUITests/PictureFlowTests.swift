import DesignSystem
import UIKit
import XCTest

final class PictureFlowTests: XCTestCase {
  override func setUp() { continueAfterFailure = false }

  @MainActor func testSendAPictureWithACaption() {
    UIPasteboard.general.image = Self.picture()
    let app = E2EApp.launch()
    signIn(app)
    openRoom(app, named: "E2E Chat")

    tapWhenReady(app.buttons[A11yIdentifiers.room.attach], "Attach menu")
    tapWhenReady(app.buttons[A11yIdentifiers.room.pastePicture], "Paste Picture")
    dismissInterruptions(app, waiting: 3)

    let caption = "e2e \(Self.marker()) picture"
    typeInto(element(app, A11yIdentifiers.room.attachmentCaption), caption, "Caption field")
    tapWhenReady(app.buttons[A11yIdentifiers.room.sendAttachments], "Send the picture")
    XCTAssertTrue(
      message(app, containing: caption).waitForExistence(timeout: Self.timeout),
      "The picture is in the timeline with its caption")
  }

  private static func picture() -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
      UIColor.systemTeal.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    }
  }
}
