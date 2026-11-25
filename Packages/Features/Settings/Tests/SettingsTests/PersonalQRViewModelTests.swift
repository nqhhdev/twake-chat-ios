import CoreImage
import Foundation
import Testing
import UIKit

@testable import Settings

@MainActor
struct PersonalQRViewModelTests {
  private final class Opened {
    var urls: [URL] = []
    var copied: [String] = []
  }

  private func makeViewModel(_ opened: Opened) -> PersonalQRViewModel {
    let viewModel = PersonalQRViewModel(userId: "@alice:example.org") { opened.copied.append($0) }
    viewModel.openLink = { opened.urls.append($0) }
    return viewModel
  }

  @Test func theLinkIsTheMatrixToLinkOfTheUser() {
    let viewModel = PersonalQRViewModel(userId: "@alice:example.org") { _ in }
    #expect(viewModel.link?.absoluteString == "https://matrix.to/#/@alice:example.org")
  }

  @Test func copyingPutsTheLinkOnThePasteboardAndShowsIt() {
    let opened = Opened()
    let viewModel = makeViewModel(opened)
    viewModel.copyLink()
    #expect(opened.copied == ["https://matrix.to/#/@alice:example.org"])
    #expect(viewModel.didCopyLink)
    viewModel.linkCopyShown()
    #expect(!viewModel.didCopyLink)
  }

  @Test func scanningIsOfferedOnlyWhenTheAppCanOpenLinks() {
    let viewModel = PersonalQRViewModel(userId: "@alice:example.org") { _ in }
    #expect(!viewModel.canScan)
    viewModel.openLink = { _ in }
    #expect(viewModel.canScan)
  }

  @Test(arguments: [
    "https://matrix.to/#/@bob:example.org",
    "https://matrix.to/#/%23team%3Aexample.org?via=example.org",
    "twake.chat://chat/@bob:example.org",
    "matrix:u/bob:example.org",
    "https://links.twake.app/chat/%40bob%3Aexample.org?fallback=https://sign-up.twake.app",
    "  https://matrix.to/#/@bob:example.org\n",
  ])
  func aMatrixLinkOpensOnceTheScannerCloses(_ code: String) {
    let opened = Opened()
    let viewModel = makeViewModel(opened)
    #expect(viewModel.scanned(code))
    #expect(viewModel.scanError == nil)
    #expect(opened.urls.isEmpty)
    viewModel.scannerClosed()
    #expect(
      opened.urls.map(\.absoluteString) == [code.trimmingCharacters(in: .whitespacesAndNewlines)])
    #expect(viewModel.pendingLink == nil)
  }

  @Test(arguments: ["https://example.org/page", "hello", "WIFI:S:home;T:WPA;P:secret;;", ""])
  func anythingElseShowsAnErrorAndOpensNothing(_ code: String) {
    let opened = Opened()
    let viewModel = makeViewModel(opened)
    #expect(!viewModel.scanned(code))
    #expect(viewModel.scanError != nil)
    viewModel.scannerClosed()
    #expect(opened.urls.isEmpty)
    #expect(viewModel.scanError == nil)
  }

  @Test func theUsersOwnCodeIsNotOpened() {
    let opened = Opened()
    let viewModel = makeViewModel(opened)
    #expect(!viewModel.scanned("https://matrix.to/#/@alice:example.org"))
    #expect(viewModel.scanError == "This is your own QR code.")
    viewModel.scannerClosed()
    #expect(opened.urls.isEmpty)
  }

  @Test func aGoodScanAfterABadOneClearsTheError() {
    let opened = Opened()
    let viewModel = makeViewModel(opened)
    viewModel.scanned("hello")
    #expect(viewModel.scanned("https://matrix.to/#/@bob:example.org"))
    #expect(viewModel.scanError == nil)
  }

  @Test func closingTheScannerWithoutACodeOpensNothing() {
    let opened = Opened()
    let viewModel = makeViewModel(opened)
    viewModel.scannerClosed()
    #expect(opened.urls.isEmpty)
  }

  @Test func theQRCodeImageReadsBackAsTheLink() throws {
    let link = "https://matrix.to/#/@alice:example.org"
    let image = try #require(QRCodeImage.make(from: link))
    let cgImage = try #require(image.cgImage)
    let detector = try #require(
      CIDetector(
        ofType: CIDetectorTypeQRCode, context: nil,
        options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
    let messages = detector.features(in: CIImage(cgImage: cgImage)).compactMap {
      ($0 as? CIQRCodeFeature)?.messageString
    }
    #expect(messages == [link])
  }
}
