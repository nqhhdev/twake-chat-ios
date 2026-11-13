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
public protocol LinkPreviewRepository: Sendable {
  /// The preview of `url`, or `nil` when the server has none.
  func preview(of url: URL) async -> LinkPreview?
}
