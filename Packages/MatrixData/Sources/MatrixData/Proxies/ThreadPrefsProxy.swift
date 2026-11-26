import Domain
import Foundation
import MatrixRustSDK

/// `ThreadPrefsRepository` on the account data the web client writes (`app.twake.chat.thread_prefs`), with the web's
/// mute push rule. Nothing here logs message content (ADR 0009).
public actor ThreadPrefsProxy: ThreadPrefsRepository {
  private let clientProxy: @Sendable () async -> ClientProxy?
  private let capabilities: (any ServerCapabilitiesRepository)?

  static let activeRoomLimit = 10

  public init(
    authentication: MatrixAuthenticationRepository,
    capabilities: (any ServerCapabilitiesRepository)? = nil
  ) {
    clientProxy = { await authentication.clientProxy }
    self.capabilities = capabilities
  }

  public func threadPrefs() async -> [ThreadPrefEntry] {
    guard let client = await clientProxy()?.client,
      let json = try? await client.accountData(eventType: ThreadPrefs.accountDataType)
    else { return [] }
    return ThreadPrefs.entries(fromJSON: Data(json.utf8))
  }

  /// As the web's `saveThreadPref`: the thread's mute rule is removed, added again for `mute`, then the account data
  /// is written, so the server and the other clients stay silent too.
  public func setThreadPref(_ pref: ThreadPref, roomId: String, threadId: String)
    async throws(TimelineError)
  {
    guard let client = await clientProxy()?.client else { throw .notSignedIn }
    let entries = ThreadPrefs.with(
      await threadPrefs(), roomId: roomId, threadId: threadId, pref: pref)
    guard let data = ThreadPrefs.json(entries), let content = String(data: data, encoding: .utf8)
    else { throw .requestFailed }
    let ruleId = ThreadPrefs.muteRuleId(threadId: threadId)
    do {
      await Self.deleteOverrideRule(ruleId, client: client)
      if pref == .mute {
        try await client.getNotificationSettings().setCustomPushRule(
          ruleId: ruleId, ruleKind: .override, actions: [],
          conditions: Self.muteConditions(roomId: roomId, threadId: threadId))
      }
      try await client.setAccountData(eventType: ThreadPrefs.accountDataType, content: content)
      await subscribe(pref, roomId: roomId, threadId: threadId, client: client)
    } catch {
      DebugLog.failure("setThreadPref", error)
      throw .requestFailed
    }
  }

  /// The web's conditions: the room, a `m.thread` relation, to this root.
  static func muteConditions(roomId: String, threadId: String) -> [PushCondition] {
    [
      .eventMatch(key: "room_id", pattern: roomId),
      .eventPropertyIs(key: "content.m\\.relates_to.rel_type", value: .string(value: "m.thread")),
      .eventPropertyIs(key: "content.m\\.relates_to.event_id", value: .string(value: threadId)),
    ]
  }

  /// The pinned SDK can add a custom push rule but not delete one: `DELETE /pushrules/global/override/{ruleId}`. A
  /// rule that does not exist answers 404, which is fine, as on the web.
  private static func deleteOverrideRule(_ ruleId: String, client: Client) async {
    guard
      let request = ClientServerRequest.make(
        client: client, path: "pushrules/global/override/\(ClientServerRequest.encode(ruleId))",
        method: "DELETE")
    else { return }
    _ = await ClientServerRequest.succeeds(request)
  }

  public func followedThreads() async -> [FollowedThread] {
    guard let client = await clientProxy()?.client else { return [] }
    let followed = await threadPrefs().filter { $0.pref != .unfollow }
    var result: [FollowedThread?] = Array(repeating: nil, count: followed.count)
    for chunk in stride(from: 0, to: followed.count, by: 8) {
      await withTaskGroup(of: (Int, FollowedThread?).self) { group in
        for index in chunk..<min(chunk + 8, followed.count) {
          let entry = followed[index]
          group.addTask { (index, await Self.thread(for: entry, client: client)) }
        }
        for await (index, thread) in group { result[index] = thread }
      }
    }
    return result.compactMap { $0 }
  }

  /// One followed thread with its root's preview; `nil` when its room is not joined here.
  private static func thread(for entry: ThreadPrefEntry, client: Client) async -> FollowedThread? {
    guard let room = try? client.getRoom(roomId: entry.roomId), room.membership() == .joined
    else { return nil }
    let roomName = room.displayName() ?? entry.roomId
    guard let event = try? await room.loadOrFetchEvent(eventId: entry.threadId) else {
      return FollowedThread(
        entry: entry, roomName: roomName, rootSenderName: nil, rootText: nil, date: nil)
    }
    var text: String?
    if case .messageLike(let content)? = try? event.content() {
      text = NotificationContentProxy.body(of: content)
    }
    let sender = event.senderId()
    let name =
      ((try? await room.memberDisplayName(userId: sender)) ?? nil)
      .flatMap { $0.isEmpty ? nil : $0 } ?? sender
    return FollowedThread(
      entry: entry, roomName: roomName, rootSenderName: name, rootText: text,
      date: Date(timeIntervalSince1970: TimeInterval(event.timestamp()) / 1000))
  }

  private func subscribe(_ pref: ThreadPref, roomId: String, threadId: String, client: Client)
    async
  {
    guard let capabilities,
      ThreadPrefs.usesSubscriptions(await capabilities.current().unstableFeatures),
      let room = try? client.getRoom(roomId: roomId)
    else { return }
    do {
      try await room.setThreadSubscription(
        threadRootEventId: threadId, subscribed: ThreadPrefs.isSubscribed(pref))
    } catch {
      DebugLog.failure("setThreadSubscription", error)
    }
  }

  public func activeThreads(inRooms roomIds: [String]) async -> [FollowedThread] {
    guard let client = await clientProxy()?.client else { return [] }
    let entries = await threadPrefs()
    let rooms = roomIds.prefix(Self.activeRoomLimit).compactMap {
      try? client.getRoom(roomId: $0)
    }
    return await withTaskGroup(of: [FollowedThread].self) { group in
      for room in rooms where room.membership() == .joined {
        group.addTask { await Self.activeThreads(in: room, entries: entries) }
      }
      var all: [FollowedThread] = []
      for await threads in group { all += threads }
      return all
    }
  }

  private static func activeThreads(in room: Room, entries: [ThreadPrefEntry]) async
    -> [FollowedThread]
  {
    let service = room.threadListService()
    do {
      try await service.paginate()
    } catch {
      DebugLog.failure("threadList.paginate", error)
      return []
    }
    let roomId = room.id()
    let roomName = room.displayName() ?? roomId
    return service.items().compactMap { item in
      let candidate = ThreadActivityCandidate(
        roomId: roomId, threadId: item.rootEvent.eventId, rootIsOwn: item.rootEvent.isOwn,
        latestIsOwn: item.latestEvent?.isOwn)
      guard ThreadPrefs.isActive(candidate, entries: entries), let latest = item.latestEvent
      else { return nil }
      return FollowedThread(
        entry: ThreadPrefEntry(
          roomId: roomId, threadId: item.rootEvent.eventId,
          pref: ThreadPrefs.pref(of: candidate, in: entries) ?? .follow),
        roomName: roomName, rootSenderName: name(of: item.rootEvent),
        rootText: item.rootEvent.content.flatMap(TimelineItemMapper.line(of:)),
        date: Date(timeIntervalSince1970: TimeInterval(latest.timestamp) / 1000),
        latestSenderName: name(of: latest),
        latestText: latest.content.flatMap(TimelineItemMapper.line(of:)),
        replyCount: Int(item.numReplies))
    }
  }

  private static func name(of event: ThreadListItemEvent) -> String {
    if case .ready(let displayName, _, _) = event.senderProfile, let displayName,
      !displayName.isEmpty
    {
      return displayName
    }
    return event.sender
  }
}
