import Domain
import Foundation
import MatrixRustSDK

extension TimelineProxy {
  public func botCommands() async -> [BotCommand] {
    guard let opened,
      let request = ClientServerRequest.make(
        client: opened.client.client, path: "rooms/\(ClientServerRequest.encode(roomId))/state"),
      let (data, response) = try? await URLSession.shared.data(for: request),
      (response as? HTTPURLResponse)?.statusCode == 200,
      let events = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else { return [] }
    var commands: [BotCommand] = []
    for event in events {
      guard let type = event["type"] as? String,
        type == "org.matrix.msc4332.commands" || type == "m.bot.commands",
        let bot = event["state_key"] as? String, !bot.isEmpty,
        let content = event["content"] as? [String: Any],
        let member = try? await opened.room.member(userId: bot), member.membership == .join
      else { continue }
      commands += BotCommand.commands(botUserId: bot, content: content)
    }
    return commands
  }

  public func gifsEnabled() async -> Bool {
    await gifsEnabled(in: roomId)
  }

  public func gifsEnabled(in roomId: String) async -> Bool {
    guard let opened, let room = try? opened.client.client.getRoom(roomId: roomId) else {
      return true
    }
    if await room.isDirect() { return true }
    let encoded = ClientServerRequest.encode(roomId)
    guard
      let request = ClientServerRequest.make(
        client: opened.client.client, path: "rooms/\(encoded)/state/\(Self.gifsStateType)/"),
      let content = await ClientServerRequest.object(request)
    else { return true }
    return Self.gifsEnabled(content)
  }

  static let gifsStateType = ChannelSettings.gifsStateType

  static func gifsEnabled(_ content: [String: Any]) -> Bool {
    (content["enabled"] as? Bool) != false
  }

  public func threads() async -> [ThreadListEntry] {
    guard let room = opened?.room else { return [] }
    let service = room.threadListService()
    do {
      try await service.paginate()
    } catch {
      DebugLog.failure("threadList", error)
      return []
    }
    return service.items().map(TimelineItemMapper.threadEntry)
      .sorted { $0.latestDate > $1.latestDate }
  }

  public func editHistory(of eventId: String) async -> [MessageVersion]? {
    guard let opened else { return nil }
    guard (try? await opened.room.latestEncryptionState()) == .notEncrypted else {
      return await EncryptedEditHistory.versions(
        of: eventId, roomId: roomId, room: opened.room, client: opened.client.client)
    }
    let room = ClientServerRequest.encode(roomId)
    let event = ClientServerRequest.encode(eventId)
    let client = opened.client.client
    async let original = Self.data(
      ClientServerRequest.make(client: client, path: "rooms/\(room)/event/\(event)"))
    async let relations = Self.data(
      ClientServerRequest.make(
        client: client, path: "rooms/\(room)/relations/\(event)/m.replace?limit=50", version: "v1"))
    return MessageVersion.versions(original: await original, relations: await relations)
  }

  static func data(_ request: URLRequest?) async -> Data? {
    guard let request, let (data, response) = try? await URLSession.shared.data(for: request),
      (response as? HTTPURLResponse)?.statusCode == 200
    else { return nil }
    return data
  }
}
