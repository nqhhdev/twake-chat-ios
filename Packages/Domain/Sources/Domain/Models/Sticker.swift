import Foundation

public struct Sticker: Sendable, Equatable, Identifiable {
  public let id: String
  public let body: String
  public let url: String
  public let media: MediaReference

  public init(id: String, body: String, url: String, media: MediaReference) {
    self.id = id
    self.body = body
    self.url = url
    self.media = media
  }
}

public struct StickerPack: Sendable, Equatable, Identifiable {
  public let id: String
  public let name: String
  public let avatar: MediaReference?
  public let stickers: [Sticker]

  public init(id: String, name: String, avatar: MediaReference?, stickers: [Sticker]) {
    self.id = id
    self.name = name
    self.avatar = avatar
    self.stickers = stickers
  }
}
