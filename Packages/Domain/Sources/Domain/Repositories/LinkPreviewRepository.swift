import Foundation

/// What a web link shows before it is opened: the page's title, description, site and picture.
public struct LinkPreview: Sendable, Equatable {
  public let url: URL
  public let title: String?
  public let description: String?
  public let siteName: String?
  /// The page's picture, kept by the homeserver.
  public let image: MediaReference?

  public init(
    url: URL, title: String?, description: String?, siteName: String?, image: MediaReference?
  ) {
    self.url = url
    self.title = title
    self.description = description
    self.siteName = siteName
    self.image = image
  }

  /// A preview with nothing to show is not shown.
  public var isEmpty: Bool { title == nil && description == nil && image == nil }
}

/// Link previews from the homeserver (Flutter `preview_url`): the server fetches the page, so the device never
/// contacts the linked site. Implemented in MatrixData (ADR 0006).
/// No preview in an encrypted room, nor in a room whose encryption is unknown: asking for one would tell the
/// homeserver the links of an end-to-end encrypted chat (web D211, security audit 2026-10-16). The gate is in the
/// repository, which every caller passes.
public protocol LinkPreviewRepository: Sendable {
  /// The preview of `url` posted in `roomId`, or `nil` when the server has none or the room is encrypted.
  func preview(of url: URL, inRoom roomId: String) async -> LinkPreview?
}
