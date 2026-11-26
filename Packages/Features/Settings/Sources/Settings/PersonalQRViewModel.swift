import Domain
import Foundation
import Observation
import UIKit

@MainActor @Observable
public final class PersonalQRViewModel {
  public let userId: String
  public private(set) var scanError: String?
  public private(set) var didCopyLink = false
  public private(set) var pendingLink: URL?
  @ObservationIgnored public var openLink: (@MainActor (URL) -> Void)?
  @ObservationIgnored private let copy: @MainActor (String) -> Void

  public init(
    userId: String,
    copy: @escaping @MainActor (String) -> Void = { UIPasteboard.general.string = $0 }
  ) {
    self.userId = userId
    self.copy = copy
  }

  public var link: URL? { MatrixLink.user(id: userId).url }

  public var canScan: Bool { openLink != nil }

  public func copyLink() {
    guard let link else { return }
    copy(link.absoluteString)
    didCopyLink = true
  }

  public func linkCopyShown() { didCopyLink = false }

  @discardableResult
  public func scanned(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed), let link = MatrixLink(url: url) else {
      scanError = localized("This QR code is not a Twake Chat or Matrix link.")
      return false
    }
    if link == .user(id: userId) {
      scanError = localized("This is your own QR code.")
      return false
    }
    scanError = nil
    pendingLink = url
    return true
  }

  public func scannerClosed() {
    scanError = nil
    guard let url = pendingLink else { return }
    pendingLink = nil
    openLink?(url)
  }
}
