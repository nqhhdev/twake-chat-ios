import Foundation

public struct NewSpace: Sendable, Equatable {
  public var name: String
  public var topic: String
  public var isPublic: Bool
  public var parentId: String?

  public init(
    name: String = "", topic: String = "", isPublic: Bool = false, parentId: String? = nil
  ) {
    self.name = name
    self.topic = topic
    self.isPublic = isPublic
    self.parentId = parentId
  }

  public static let roomType = "m.space"
  static let adminLevel = 100
  static let memberEvents = [
    "org.matrix.msc3401.call.member", "org.matrix.msc4332.commands", "m.bot.commands",
    "org.matrix.msc3381.poll.response", "m.poll.response", "app.twake.chat.thread_resolved",
    "app.twake.chat.assistant_consent",
  ]
  static let publicPageType = "app.twake.chat.public_page"

  public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

  public var canCreate: Bool { !trimmedName.isEmpty }

  public static func via(_ roomId: String, ownServer: String?) -> [String] {
    let named = roomId.firstIndex(of: ":").map { String(roomId[roomId.index(after: $0)...]) }
    var servers: [String] = []
    for server in [named, ownServer].compactMap({ $0 }) where !servers.contains(server) {
      servers.append(server)
    }
    return servers
  }

  public static func childContent(childId: String, ownServer: String?) -> [String: Any] {
    ["via": via(childId, ownServer: ownServer)]
  }

  public func createRoomBody(ownServer: String?, avatarURL: String? = nil) -> [String: Any] {
    var events: [String: Any] = Dictionary(
      uniqueKeysWithValues: Self.memberEvents.map { ($0, 0 as Any) })
    events[Self.publicPageType] = Self.adminLevel
    var body: [String: Any] = [
      "name": trimmedName,
      "preset": isPublic ? "public_chat" : "private_chat",
      "creation_content": ["type": Self.roomType],
      "power_level_content_override": ["events": events],
    ]
    let topic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
    if !topic.isEmpty { body["topic"] = topic }
    if isPublic { body["visibility"] = "public" }
    var state: [[String: Any]] = []
    if let avatarURL {
      state.append(["type": "m.room.avatar", "state_key": "", "content": ["url": avatarURL]])
    }
    if let parentId {
      state.append([
        "type": "m.space.parent", "state_key": parentId,
        "content": ["via": Self.via(parentId, ownServer: ownServer), "canonical": true],
      ])
      if !isPublic {
        state.append([
          "type": "m.room.join_rules", "state_key": "",
          "content": [
            "join_rule": "restricted",
            "allow": [["type": "m.room_membership", "room_id": parentId]],
          ],
        ])
      }
    }
    body["initial_state"] = state
    return body
  }
}
