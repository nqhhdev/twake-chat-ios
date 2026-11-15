import Foundation

/// One saved message, as the web client keeps it in the account data `app.twake.chat.saved_messages`
/// (`{ "messages": [{ "roomId", "eventId", "savedAt" }] }`, newest first, at most 200), so both apps share the list.
public struct SavedRef: Sendable, Equatable, Hashable, Identifiable {
  public let roomId: String
  public let eventId: String
  /// When it was saved, in milliseconds since 1970.
  public let savedAt: Int64

  public var id: String { roomId + "|" + eventId }

  public init(roomId: String, eventId: String, savedAt: Int64) {
    self.roomId = roomId
    self.eventId = eventId
    self.savedAt = savedAt
  }
}

/// A saved message with what the list shows of it.
public struct SavedMessage: Sendable, Equatable, Identifiable {
  public let ref: SavedRef
  public let roomName: String
  public let senderName: String?
  /// A preview of the message; `nil` when it could not be loaded (deleted, or not decrypted yet).
  public let text: String?
  public let date: Date?
  public var id: String { ref.id }

  public init(ref: SavedRef, roomName: String, senderName: String?, text: String?, date: Date?) {
    self.ref = ref
    self.roomName = roomName
    self.senderName = senderName
    self.text = text
    self.date = date
  }
}

public enum SavedMessages {
  public static let accountDataType = "app.twake.chat.saved_messages"
  public static let maxSaved = 200

  /// The refs of the account data content; entries that are not well formed are left out, as the web reads them.
  public static func refs(fromJSON data: Data?) -> [SavedRef] {
    guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let list = object["messages"] as? [[String: Any]]
    else { return [] }
    return list.compactMap { entry in
      guard let roomId = entry["roomId"] as? String, let eventId = entry["eventId"] as? String,
        let savedAt = entry["savedAt"] as? NSNumber
      else { return nil }
      return SavedRef(roomId: roomId, eventId: eventId, savedAt: savedAt.int64Value)
    }
  }

  public static func json(_ refs: [SavedRef]) -> Data? {
    try? JSONSerialization.data(withJSONObject: [
      "messages": refs.map { ["roomId": $0.roomId, "eventId": $0.eventId, "savedAt": $0.savedAt] }
    ])
  }

  /// Saves or forgets one message; the newest come first, at most `maxSaved` (web `withSaved`).
  public static func with(
    _ refs: [SavedRef], roomId: String, eventId: String, saved: Bool, now: Date = .now
  ) -> [SavedRef] {
    let others = refs.filter { $0.roomId != roomId || $0.eventId != eventId }
    let list =
      saved
      ? [
        SavedRef(roomId: roomId, eventId: eventId, savedAt: Int64(now.timeIntervalSince1970 * 1000))
      ]
        + others
      : others
    return Array(list.prefix(maxSaved))
  }
}

/// The saved messages of the account. Implemented in MatrixData on the account data (ADR 0006).
public protocol SavedMessagesRepository: Sendable {
  func savedRefs() async -> [SavedRef]
  /// Saves the message, or forgets it.
  func setSaved(_ saved: Bool, roomId: String, eventId: String) async throws(TimelineError)
  /// The saved messages with their previews, newest saved first.
  func savedMessages() async -> [SavedMessage]
}
