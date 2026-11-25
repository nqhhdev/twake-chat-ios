public struct SpaceNode: Sendable, Equatable {
  public let id: String
  public let children: [String]

  public init(id: String, children: [String]) {
    self.id = id
    self.children = children
  }
}

public enum SpaceGraph {
  public static func descendants(_ nodes: [SpaceNode]) -> [String: [String]] {
    var children: [String: [String]] = [:]
    for node in nodes { children[node.id, default: []].append(contentsOf: node.children) }
    var result: [String: [String]] = [:]
    for id in children.keys {
      var seen: Set<String> = [id]
      var queue = children[id] ?? []
      var order: [String] = []
      var index = 0
      while index < queue.count {
        let child = queue[index]
        index += 1
        guard seen.insert(child).inserted else { continue }
        order.append(child)
        queue.append(contentsOf: children[child] ?? [])
      }
      result[id] = order
    }
    return result
  }
}

public struct SpaceUnread: Sendable, Equatable {
  public let unread: Int
  public let mentions: Int
  public let muted: Int

  public init(unread: Int, mentions: Int, muted: Int) {
    self.unread = unread
    self.mentions = mentions
    self.muted = muted
  }

  public var badgeCount: Int { unread > 0 ? unread : muted }

  public var isQuiet: Bool { unread == 0 && mentions == 0 }

  public static func of(_ space: RoomSummary, in rooms: [RoomSummary]) -> SpaceUnread {
    let ids = Set(space.spaceDescendantIds)
    let under = rooms.filter { room in
      room.id != space.id && ids.contains(room.id) && !room.isInvite && !room.isArchived
        && (room.isSpace || !room.isFavourite)
    }
    var unread = 0
    var mentions = 0
    var muted = 0
    for room in [space] + under {
      let count = max(room.unreadCount, room.isMarkedUnread && !room.isSpace ? 1 : 0)
      if room.isMuted {
        muted += count
      } else {
        unread += count
        mentions += room.mentionCount
      }
    }
    return SpaceUnread(unread: unread, mentions: mentions, muted: muted)
  }
}
