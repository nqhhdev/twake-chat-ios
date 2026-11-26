import Domain
import Foundation
import MatrixRustSDK

extension TimelineProxy {
  public func stickerPacks() async -> [StickerPack] {
    var seen = Set<String>()
    return await imagePacks().compactMap { pack in
      ImagePackMapper.pack(
        id: pack.id, content: pack.content, fallbackName: pack.fallbackName,
        source: Self.mediaSourceJSON)
    }
    .filter { seen.insert($0.id).inserted }
  }

  public func emotes() async -> [Emote] {
    var seen = Set<String>()
    let emotes = await imagePacks().flatMap { pack in
      ImagePackMapper.emotes(content: pack.content, source: Self.mediaSourceJSON)
    }
    .filter { seen.insert($0.shortcode).inserted }
    knownEmotes = Dictionary(emotes.map { ($0.shortcode, $0.url) }, uniquingKeysWith: { a, _ in a })
    return emotes
  }

  static func mediaSourceJSON(_ url: String) -> String? {
    try? MediaSource.fromUrl(url: url).toJson()
  }

  private struct PackContent: @unchecked Sendable {
    let id: String
    let content: [String: Any]
    let fallbackName: String
  }

  private func imagePacks() async -> [PackContent] {
    guard let opened else { return [] }
    let client = opened.client.client
    var packs: [PackContent] = []
    if let user = ImagePackMapper.eventContent(
      try? await client.accountData(eventType: ImagePackMapper.userPackType))
    {
      packs.append(PackContent(id: "user", content: user, fallbackName: localized("My stickers")))
    }
    let room = ClientServerRequest.encode(roomId)
    if let request = ClientServerRequest.make(client: client, path: "rooms/\(room)/state"),
      let data = await Self.data(request),
      let events = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    {
      for event in events where event["type"] as? String == ImagePackMapper.roomPackType {
        guard let key = event["state_key"] as? String,
          let content = event["content"] as? [String: Any]
        else { continue }
        packs.append(
          PackContent(
            id: "room:\(roomId):\(key)", content: content,
            fallbackName: key.isEmpty ? localized("Chat stickers") : key))
      }
    }
    let packRooms = ImagePackMapper.eventContent(
      try? await client.accountData(eventType: ImagePackMapper.packRoomsType))
    for packRoom in packRooms.map(ImagePackMapper.packRooms) ?? [] where packRoom.roomId != roomId {
      let other = packRoom.roomId
      let key = packRoom.stateKey
      let path =
        "rooms/\(ClientServerRequest.encode(other))/state/\(ImagePackMapper.roomPackType)/"
        + ClientServerRequest.encode(key)
      guard let request = ClientServerRequest.make(client: client, path: path),
        let content = await ClientServerRequest.object(request)
      else { continue }
      packs.append(
        PackContent(
          id: "room:\(other):\(key)", content: content,
          fallbackName: key.isEmpty ? "Stickers" : key))
    }
    return packs
  }

  public func send(sticker: Sticker) async throws(TimelineError) {
    let room = try openedState().room
    let content = ImagePackMapper.stickerContent(sticker, threadRoot: threadRoot)
    guard let data = try? JSONSerialization.data(withJSONObject: content),
      let json = String(data: data, encoding: .utf8)
    else { throw .requestFailed }
    do {
      try await room.sendRaw(eventType: "m.sticker", content: json)
    } catch {
      throw Self.failure("sendSticker", error)
    }
  }
}
