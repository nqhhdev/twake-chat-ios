import Domain
import Foundation
import MatrixRustSDK

/// `PeopleRepository` on the SDK client (ADR 0006): the user directory, direct chats and new groups. Nothing here logs.
public actor PeopleProxy: PeopleRepository {
  /// How many people one search returns.
  static let searchLimit: UInt64 = 30

  private let clientProxy: @Sendable () async -> ClientProxy?
  private let lookup = TwakeContactLookup()
  /// The ToM server found for this account, looked up once.
  private var tom: (baseURL: URL, serverName: String)??

  public init(authentication: MatrixAuthenticationRepository) {
    clientProxy = { await authentication.clientProxy }
  }

  public func search(_ text: String) async throws(PeopleError) -> [Person] {
    let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty else { return [] }
    let client = try await client()
    let ownUserId = try? client.userId
    var people: [Person] = []
    // Twake's address book first, as the Flutter app searches it; the Matrix user directory adds whoever it misses.
    if let tom = await tomServer(ownUserId), let token = try? client.client.session().accessToken,
      let matches = try? await lookup.search(
        term, limit: Int(Self.searchLimit), tom: tom.baseURL, serverName: tom.serverName,
        accessToken: token)
    {
      people = matches.map { Person(id: $0.userId, displayName: $0.displayName) }
    }
    if let directory = try? await client.client.searchUsers(
      searchTerm: term, limit: Self.searchLimit)
    {
      for profile in directory.results where !people.contains(where: { $0.id == profile.userId }) {
        people.append(Person(id: profile.userId, displayName: profile.displayName))
      }
    }
    people.removeAll { $0.id == ownUserId }
    // A full Matrix id that neither lists can still be invited.
    if term.hasPrefix("@"), term.contains(":"), !people.contains(where: { $0.id == term }) {
      people.insert(Person(id: term, displayName: nil), at: 0)
    }
    return people
  }

  private func tomServer(_ userId: String?) async -> (baseURL: URL, serverName: String)? {
    if let tom { return tom }
    guard let userId else { return nil }
    let found = await lookup.tomServer(forUserId: userId)
    tom = .some(found)
    return found
  }

  public func directChat(with userId: String) async throws(PeopleError) -> String {
    let client = try await client()
    if let existing = try? client.client.getDmRoom(userId: userId) { return existing.id() }
    do {
      return try await client.client.createRoom(
        request: CreateRoomParameters(
          name: nil, isEncrypted: true, isDirect: true, visibility: .private,
          preset: .trustedPrivateChat,
          invite: [userId]))
    } catch {
      throw .requestFailed
    }
  }

  public func existingDirectChat(with userId: String) async -> String? {
    guard let client = try? await client() else { return nil }
    return (try? client.client.getDmRoom(userId: userId))?.id()
  }

  public func startDirectChat(with userId: String, firstMessage: String) async throws(PeopleError)
    -> String
  {
    let roomId = try await directChat(with: userId)
    let client = try await client()
    do {
      // The message goes to the room's send queue, which the SDK keeps and sends, so nothing here needs to stay
      // alive once it is queued.
      guard let room = try client.client.getRoom(roomId: roomId) else {
        throw PeopleError.requestFailed
      }
      _ = try await room.timeline().send(msg: TimelineProxy.content(firstMessage))
    } catch {
      throw .requestFailed
    }
    return roomId
  }

  public func createGroup(name: String, inviting userIds: [String]) async throws(PeopleError)
    -> String
  {
    let client = try await client()
    do {
      return try await client.client.createRoom(
        request: CreateRoomParameters(
          name: name.trimmingCharacters(in: .whitespacesAndNewlines), isEncrypted: true,
          isDirect: false,
          visibility: .private, preset: .privateChat, invite: userIds))
    } catch {
      throw .requestFailed
    }
  }

  /// Over `/createRoom`: the SDK's `CreateRoomParameters` has no room type.
  public func createBroadcast(_ draft: BroadcastDraft, inviting userIds: [String])
    async throws(PeopleError) -> String
  {
    let client = try await client()
    guard
      let request = ClientServerRequest.make(
        client: client.client, path: "createRoom", method: "POST",
        json: Self.broadcastBody(draft, inviting: userIds)),
      let roomId = await ClientServerRequest.object(request)?["room_id"] as? String
    else { throw .requestFailed }
    return roomId
  }

  /// The `/createRoom` body of a Broadcast (web D90): typed `app.twake.chat.page`, posting from moderator (50) up,
  /// reactions open to followers when chosen. An open one is a public chat in the directory with an address and a
  /// history anyone reads; one on approval is in the directory with the `knock` join rule; one on invitation is
  /// private and encrypted.
  static func broadcastBody(_ draft: BroadcastDraft, inviting userIds: [String]) -> [String: Any] {
    // The override replaces the default `events` map, so it is given whole: the levels Synapse sets by default.
    var events: [String: Int] = [
      "m.room.name": 50, "m.room.avatar": 50, "m.room.canonical_alias": 50, "m.room.topic": 50,
      "m.room.power_levels": 100, "m.room.history_visibility": 100, "m.room.encryption": 100,
      "m.room.tombstone": 100, "m.room.server_acl": 100, "app.twake.chat.page_style": 50,
    ]
    if draft.allowsReactions { events["m.reaction"] = 0 }
    var body: [String: Any] = [
      "name": draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
      "creation_content": ["type": BroadcastDraft.roomType],
      "power_level_content_override": ["events_default": 50, "events": events],
      "invite": userIds,
    ]
    let topic = draft.topic.trimmingCharacters(in: .whitespacesAndNewlines)
    if !topic.isEmpty { body["topic"] = topic }
    var state: [[String: Any]] = []
    switch draft.access {
    case .open:
      body["preset"] = "public_chat"
      body["visibility"] = "public"
      body["room_alias_name"] = draft.slug
      state.append(
        [
          "type": "m.room.history_visibility", "state_key": "",
          "content": ["history_visibility": "world_readable"],
        ])
    case .approval:
      body["preset"] = "private_chat"
      body["visibility"] = "public"
      state.append([
        "type": "m.room.join_rules", "state_key": "", "content": ["join_rule": "knock"],
      ])
    case .invitation:
      body["preset"] = "private_chat"
      body["visibility"] = "private"
      state.append(
        [
          "type": "m.room.encryption", "state_key": "",
          "content": ["algorithm": "m.megolm.v1.aes-sha2"],
        ])
    }
    body["initial_state"] = state
    return body
  }

  private func client() async throws(PeopleError) -> ClientProxy {
    guard let client = await clientProxy() else { throw .notSignedIn }
    return client
  }
}
