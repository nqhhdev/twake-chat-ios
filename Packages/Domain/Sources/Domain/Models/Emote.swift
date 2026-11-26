import Foundation

public struct Emote: Sendable, Equatable, Identifiable {
  public let shortcode: String
  public let url: String
  public let media: MediaReference

  public var id: String { shortcode }

  public init(shortcode: String, url: String, media: MediaReference) {
    self.shortcode = shortcode
    self.url = url
    self.media = media
  }

  public static func matching(_ query: String, in emotes: [Emote], limit: Int = 6) -> [Emote] {
    let query = query.lowercased()
    let prefixed = emotes.filter { $0.shortcode.lowercased().hasPrefix(query) }
    let contained = emotes.filter {
      !$0.shortcode.lowercased().hasPrefix(query) && $0.shortcode.lowercased().contains(query)
    }
    return Array((prefixed + contained).prefix(limit))
  }
}
