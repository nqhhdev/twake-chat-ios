import Domain
import Foundation

enum ImagePackMapper {
  static let roomPackType = "im.ponies.room_emotes"
  static let userPackType = "im.ponies.user_emotes"
  static let packRoomsType = "im.ponies.emote_rooms"

  static func pack(
    id: String, content: [String: Any], fallbackName: String,
    source: (String) -> String?
  ) -> StickerPack? {
    guard let images = content["images"] as? [String: Any] else { return nil }
    let pack = content["pack"] as? [String: Any] ?? [:]
    let packUsage = pack["usage"] as? [String]
    var stickers: [Sticker] = []
    for shortcode in images.keys.sorted() {
      guard let image = images[shortcode] as? [String: Any],
        let url = image["url"] as? String, url.hasPrefix("mxc://"),
        isSticker(image["usage"] as? [String] ?? packUsage),
        let reference = source(url)
      else { continue }
      let info = image["info"] as? [String: Any] ?? [:]
      let body = (image["body"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? shortcode
      stickers.append(
        Sticker(
          id: id + "/" + shortcode, body: body, url: url,
          media: MediaReference(
            source: reference, mimeType: info["mimetype"] as? String, size: info["size"] as? Int,
            width: info["w"] as? Int, height: info["h"] as? Int)))
    }
    guard !stickers.isEmpty else { return nil }
    let name = (pack["display_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
    let avatar = (pack["avatar_url"] as? String).flatMap(source).map {
      MediaReference(source: $0, mimeType: "image/*")
    }
    return StickerPack(id: id, name: name, avatar: avatar, stickers: stickers)
  }

  static func isSticker(_ usage: [String]?) -> Bool {
    guard let usage, !usage.isEmpty else { return true }
    return usage.contains("sticker")
  }

  static func packRooms(_ content: [String: Any]) -> [(roomId: String, stateKey: String)] {
    guard let rooms = content["rooms"] as? [String: Any] else { return [] }
    return rooms.keys.sorted().flatMap { roomId -> [(roomId: String, stateKey: String)] in
      guard let keys = rooms[roomId] as? [String: Any] else { return [] }
      return keys.keys.sorted().map { (roomId, $0) }
    }
  }

  static func eventContent(_ json: String?) -> [String: Any]? {
    guard let json, let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
      let dictionary = object as? [String: Any]
    else { return nil }
    if dictionary["type"] is String, let content = dictionary["content"] as? [String: Any] {
      return content
    }
    return dictionary
  }

  static func stickerContent(_ sticker: Sticker, threadRoot: String?) -> [String: Any] {
    var info: [String: Any] = [:]
    if let width = sticker.media.width { info["w"] = width }
    if let height = sticker.media.height { info["h"] = height }
    if let mimeType = sticker.media.mimeType { info["mimetype"] = mimeType }
    if let size = sticker.media.size { info["size"] = size }
    var content: [String: Any] = ["body": sticker.body, "url": sticker.url, "info": info]
    if let threadRoot {
      content["m.relates_to"] = [
        "rel_type": "m.thread", "event_id": threadRoot, "is_falling_back": true,
        "m.in_reply_to": ["event_id": threadRoot],
      ]
    }
    return content
  }
}
