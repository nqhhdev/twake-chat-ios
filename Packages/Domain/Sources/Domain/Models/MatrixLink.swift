import Foundation

/// A link to a Matrix room, message or person, as the Flutter `UrlLauncher.openMatrixToUrl` reads them:
/// `https://matrix.to/#/…`, the app's `twake.chat://chat/…`, and the `matrix:` scheme (`matrix:r/…`, `matrix:roomid/…`,
/// `matrix:u/…`, with `/e/<event>`).
public enum MatrixLink: Sendable, Equatable {
  /// A room by id (`!…`) or alias (`#…`), maybe one message in it, and servers that can find it.
  case room(idOrAlias: String, eventId: String?, via: [String])
  /// A person (`@…`).
  case user(id: String)

  /// The link in `url`, or `nil` when it is not a Matrix link.
  public init?(url: URL) {
    let text = url.absoluteString
    let lower = text.lowercased()
    if lower.hasPrefix("matrix:") {
      guard let link = Self.parseMatrixScheme(text) else { return nil }
      self = link
      return
    }
    let identifiers: String
    if lower.hasPrefix("https://matrix.to/#/") || lower.hasPrefix("http://matrix.to/#/") {
      identifiers = String(text[text.index(after: text.firstIndex(of: "#")!)...].dropFirst())
    } else if lower.hasPrefix("twake.chat://chat/") {
      identifiers = String(text.dropFirst("twake.chat://chat/".count))
    } else {
      return nil
    }
    guard let link = Self.parseIdentifiers(identifiers) else { return nil }
    self = link
  }

  /// The `https://matrix.to/#/…` link to share this room, message or person (spec, "matrix.to navigation"): each
  /// identifier is percent-encoded, and a room link names the servers that can find it.
  public var url: URL? {
    let path: String
    var via: [String] = []
    switch self {
    case .user(let id):
      path = Self.encode(id)
    case .room(let idOrAlias, let eventId, let servers):
      path = Self.encode(idOrAlias) + (eventId.map { "/" + Self.encode($0) } ?? "")
      via = idOrAlias.hasPrefix("!") ? servers : []
    }
    let query = via.isEmpty ? "" : "?" + via.map { "via=" + Self.encode($0) }.joined(separator: "&")
    return URL(string: "https://matrix.to/#/" + path + query)
  }

  /// The server name of a Matrix id (`@user:server`), or `nil` when it has none.
  public static func server(of id: String) -> String? {
    guard let colon = id.firstIndex(of: ":") else { return nil }
    let server = id[id.index(after: colon)...]
    return server.isEmpty ? nil : String(server)
  }

  private static func encode(_ text: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~!$@:+=")
    return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
  }

  /// `<id>[/<event>][?via=…]` after `matrix.to/#/`; the parts may be percent-encoded.
  static func parseIdentifiers(_ text: String) -> MatrixLink? {
    let (path, query) = split(text)
    let parts = path.split(separator: "/", omittingEmptySubsequences: true).map {
      String($0).removingPercentEncoding ?? String($0)
    }
    guard let primary = parts.first, let sigil = primary.first, primary.count > 1 else {
      return nil
    }
    switch sigil {
    case "@":
      return .user(id: primary)
    case "!", "#":
      let event = parts.dropFirst().first { $0.hasPrefix("$") }
      return .room(idOrAlias: primary, eventId: event, via: via(in: query))
    default:
      return nil
    }
  }

  /// `matrix:r/alias:server`, `matrix:roomid/id:server[/e/event]`, `matrix:u/user:server` (Matrix spec, URI scheme).
  static func parseMatrixScheme(_ text: String) -> MatrixLink? {
    let (path, query) = split(String(text.dropFirst("matrix:".count)))
    let parts = path.split(separator: "/", omittingEmptySubsequences: true).map {
      String($0).removingPercentEncoding ?? String($0)
    }
    guard parts.count >= 2 else { return nil }
    let event = parts.count >= 4 && parts[2] == "e" ? "$" + parts[3] : nil
    switch parts[0] {
    case "u": return .user(id: "@" + parts[1])
    case "r": return .room(idOrAlias: "#" + parts[1], eventId: event, via: via(in: query))
    case "roomid": return .room(idOrAlias: "!" + parts[1], eventId: event, via: via(in: query))
    default: return nil
    }
  }

  private static func split(_ text: String) -> (path: String, query: String?) {
    guard let mark = text.firstIndex(of: "?") else { return (text, nil) }
    return (String(text[..<mark]), String(text[text.index(after: mark)...]))
  }

  private static func via(in query: String?) -> [String] {
    guard let query else { return [] }
    return query.split(separator: "&").compactMap { pair in
      let item = pair.split(separator: "=", maxSplits: 1).map(String.init)
      guard item.count == 2, item[0] == "via" else { return nil }
      return item[1].removingPercentEncoding ?? item[1]
    }
  }
}

/// Where a room link leads for this user.
public enum RoomLinkTarget: Sendable, Equatable {
  /// The user is in the room, or invited to it: it opens.
  case member(roomId: String)
  /// The user is not in the room; it can be joined, as the Flutter public room preview offers.
  case preview(RoomLinkPreview)
}

/// What a room shows before the user joins it.
public struct RoomLinkPreview: Sendable, Equatable {
  public let idOrAlias: String
  public let name: String?
  public let topic: String?
  public let memberCount: Int
  public let avatar: MediaReference?
  /// Anyone can join (a public room); otherwise joining needs an invitation or knocking, and may fail.
  public let isPublic: Bool

  public init(
    idOrAlias: String, name: String?, topic: String?, memberCount: Int, avatar: MediaReference?,
    isPublic: Bool
  ) {
    self.idOrAlias = idOrAlias
    self.name = name
    self.topic = topic
    self.memberCount = memberCount
    self.avatar = avatar
    self.isPublic = isPublic
  }
}

public enum RoomLinkError: Error, Sendable, Equatable {
  case notSignedIn
  case notFound
  case requestFailed
}

/// Follows room links: finds the room and the user's membership, and joins it. Implemented in MatrixData (ADR 0006).
public protocol RoomLinkRepository: Sendable {
  /// Where a room link leads: the room when the user is a member, otherwise its preview.
  func target(of idOrAlias: String, via: [String]) async throws(RoomLinkError) -> RoomLinkTarget
  /// Joins the room and returns its id.
  func join(_ idOrAlias: String, via: [String]) async throws(RoomLinkError) -> String
}
