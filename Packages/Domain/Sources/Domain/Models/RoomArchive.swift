import Foundation

/// One chat the user left, as the web client keeps it in the account data `app.twake.chat.archived_rooms`
/// (`{ "rooms": [{ "roomId", "name", "isDirect", "leftAt", "avatarUrl"? }] }`, newest first, at most 200), so a chat
/// left on any device shows in the archive of every device.
public struct ArchivedRoomEntry: Sendable, Equatable {
  public let roomId: String
  public let name: String
  public let isDirect: Bool
  /// When it was left, in milliseconds since 1970.
  public let leftAt: Int64
  /// Its `mxc://` picture when it was left.
  public let avatarURL: String?

  public init(roomId: String, name: String, isDirect: Bool, leftAt: Int64, avatarURL: String? = nil)
  {
    self.roomId = roomId
    self.name = name
    self.isDirect = isDirect
    self.leftAt = leftAt
    self.avatarURL = avatarURL
  }
}

public enum RoomArchive {
  public static let accountDataType = "app.twake.chat.archived_rooms"
  public static let maxArchived = 200

  /// The entries of the account data content; malformed ones are left out, as the web reads them. Other keys of an
  /// entry (the web's `ban`) are not kept: the archive here only shows the chat.
  public static func entries(fromJSON data: Data?) -> [ArchivedRoomEntry] {
    guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let list = object["rooms"] as? [[String: Any]]
    else { return [] }
    return list.compactMap { entry in
      guard let roomId = entry["roomId"] as? String, let name = entry["name"] as? String,
        let isDirect = entry["isDirect"] as? Bool, let leftAt = entry["leftAt"] as? NSNumber
      else { return nil }
      return ArchivedRoomEntry(
        roomId: roomId, name: name, isDirect: isDirect, leftAt: leftAt.int64Value,
        avatarURL: entry["avatarUrl"] as? String)
    }
  }

  /// Adds `room` (once; the newest first) or, with `nil`, drops `roomId` (web `withArchived`). Entries are read from
  /// the raw JSON objects, so what another client added to an entry (such as `ban`) is kept.
  public static func json(updating data: Data?, roomId: String, with room: ArchivedRoomEntry?)
    -> Data?
  {
    let object =
      data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    let list = (object["rooms"] as? [[String: Any]]) ?? []
    let others = list.filter { ($0["roomId"] as? String) != roomId }
    var added: [[String: Any]] = []
    if let room {
      var entry: [String: Any] = [
        "roomId": room.roomId, "name": room.name, "isDirect": room.isDirect, "leftAt": room.leftAt,
      ]
      if let avatar = room.avatarURL { entry["avatarUrl"] = avatar }
      added = [entry]
    }
    var updated = object
    updated["rooms"] = Array((added + others).prefix(maxArchived))
    return try? JSONSerialization.data(withJSONObject: updated)
  }
}
