import XCTest

/// Flows that need more than the Synapse-only stack. They skip until their harness exists; see docs/e2e.md.
final class ScaffoldFlowTests: XCTestCase {
  /// Flow 2: a message from a cross-signed Flutter/web device in an encrypted room decrypts on iOS (#79).
  /// TODO: drive the second, crypto-capable client with twake-space-chat/e2e (`bob-*.mjs`,
  /// `scripts/seed-encryption.mjs`), and bootstrap recovery on iOS (#81).
  func testEncryptedGroupMessageDecrypts() throws {
    throw XCTSkip(
      "E2EE flow needs a crypto-capable second client (twake-space-chat/e2e node drivers); see #79, #83"
    )
  }

  /// Media: send an image, receive one from the peer and open it.
  /// TODO: seed an `m.image` from ios-bob with the media repo, and pick a photo with the simulator photo library.
  func testSendAndReceiveImage() throws {
    throw XCTSkip("Media flow is a scaffold; see #83")
  }
}
