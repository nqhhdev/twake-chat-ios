import Foundation

extension MessageVersion {
  /// An original message or one of its edits as the device decrypted it, for the edit history of an encrypted room.
  public struct Decrypted: Sendable, Equatable {
    public let id: String
    public let senderId: String
    /// The event's `body`: for an edit, its fallback text ("* " then the new text), not `m.new_content`.
    public let body: String
    public let date: Date

    public init(id: String, senderId: String, body: String, date: Date) {
      self.id = id
      self.senderId = senderId
      self.body = body
      self.date = date
    }
  }

  /// The ids of the edits in an answer of `/relations/{eventId}/m.replace`. In an encrypted room the server keeps
  /// the relation in clear and the edit encrypted, so the ids are readable; the edits must be decrypted on the device.
  public static func editIds(inRelations relations: [String: Any]) -> [String] {
    (relations["chunk"] as? [[String: Any]] ?? []).compactMap { $0["event_id"] as? String }
  }

  /// The versions of a decrypted message: the original, then its edits oldest first. Only the original's sender may
  /// edit it (spec "Event replacements"), so an edit by anyone else is left out. An edit's text is its fallback body
  /// without the leading "* ".
  public static func versions(original: Decrypted, edits: [Decrypted]) -> [MessageVersion] {
    let first = MessageVersion(id: original.id, text: original.body, date: original.date)
    let later =
      edits
      .filter { $0.senderId == original.senderId && $0.id != original.id }
      .sorted { $0.date < $1.date }
      .map { MessageVersion(id: $0.id, text: withoutFallbackMarker($0.body), date: $0.date) }
    return [first] + later
  }

  /// An edit's fallback body without its "* " marker; a body without the marker is kept as it is.
  static func withoutFallbackMarker(_ body: String) -> String {
    body.hasPrefix("* ") ? String(body.dropFirst(2)) : body
  }
}
