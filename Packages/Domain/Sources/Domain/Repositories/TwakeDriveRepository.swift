import Foundation

public struct DriveSignInRequest: Sendable, Equatable {
  public let url: URL
  public let callbackScheme: String
  public let state: String

  public init(url: URL, callbackScheme: String, state: String) {
    self.url = url
    self.callbackScheme = callbackScheme
    self.state = state
  }
}

public struct DrivePickerOptions: Sendable, Equatable {
  public let linkLabel: String
  public let attachLabel: String?
  public let maxAttachmentBytes: Int?
  public let isDark: Bool

  public init(linkLabel: String, attachLabel: String?, maxAttachmentBytes: Int?, isDark: Bool) {
    self.linkLabel = linkLabel
    self.attachLabel = attachLabel
    self.maxAttachmentBytes = maxAttachmentBytes
    self.isDark = isDark
  }
}

public struct DrivePicker: Sendable, Equatable {
  public let intentId: String
  public let url: URL
  public let client: String
  public let acknowledgement: String

  public init(intentId: String, url: URL, client: String, acknowledgement: String) {
    self.intentId = intentId
    self.url = url
    self.client = client
    self.acknowledgement = acknowledgement
  }

  public var origin: String? {
    guard let scheme = url.scheme, let host = url.host() else { return nil }
    return url.port.map { "\(scheme)://\(host):\($0)" } ?? "\(scheme)://\(host)"
  }
}

public struct DriveDocument: Sendable, Equatable, Identifiable {
  public let id: String
  public let name: String
  public let size: Int
  public let mimeType: String?
  public let sharingLink: URL?
  public let downloadLink: URL?

  public init(
    id: String, name: String, size: Int, mimeType: String?, sharingLink: URL?, downloadLink: URL?
  ) {
    self.id = id
    self.name = name
    self.size = size
    self.mimeType = mimeType
    self.sharingLink = sharingLink
    self.downloadLink = downloadLink
  }
}

public enum DrivePickerMessage: Sendable, Equatable {
  case ready
  case readyToUse
  case done([DriveDocument])
  case error
  case cancel
  case unknown

  public static func parse(_ raw: String, intentId: String) -> DrivePickerMessage? {
    guard let data = raw.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let type = object["type"] as? String
    else { return nil }
    switch type {
    case "intent-\(intentId):ready": return .ready
    case "intent-\(intentId):readyToUse": return .readyToUse
    case "intent-\(intentId):error": return .error
    case "intent-\(intentId):cancel": return .cancel
    case "intent-\(intentId):done":
      let entries = object["document"] as? [[String: Any]] ?? []
      return .done(entries.compactMap(document))
    default: return .unknown
    }
  }

  static func document(_ entry: [String: Any]) -> DriveDocument? {
    guard let id = entry["id"] as? String, let name = entry["name"] as? String,
      let size = (entry["size"] as? NSNumber)?.intValue, size >= 0
    else { return nil }
    func link(_ key: String) -> URL?? {
      guard let text = entry[key] as? String else { return .some(nil) }
      guard let url = URL(string: text), url.scheme == "https" || url.scheme == "http" else {
        return nil
      }
      return .some(url)
    }
    guard let sharing = link("sharingLink"), let download = link("downloadLink") else {
      return nil
    }
    return DriveDocument(
      id: id, name: name, size: size, mimeType: entry["mimeType"] as? String,
      sharingLink: sharing, downloadLink: download)
  }
}

public enum DriveError: Error, Sendable, Equatable {
  case unavailable
  case notSignedIn
  case cancelled
  case signInFailed
  case workplaceUnknown
  case exchangeRejected
  case intentFailed
  case tooLarge
  case downloadFailed
}

public protocol TwakeDriveRepository: Sendable {
  func isAvailable() async -> Bool

  func signInRequest() async throws(DriveError) -> DriveSignInRequest

  func completeSignIn(_ request: DriveSignInRequest, callback: URL) async throws(DriveError)

  func picker(_ options: DrivePickerOptions) async throws(DriveError) -> DrivePicker

  func download(_ document: DriveDocument, maxBytes: Int?) async throws(DriveError) -> URL

  func signOut() async
}
