import Domain
import Foundation
import MatrixRustSDK

/// `SavedMessagesRepository` on the account data the web client writes (`app.twake.chat.saved_messages`). Previews
/// come from each room's event cache, or the server. Nothing here logs: the previews are message content (ADR 0009).
public actor SavedMessagesProxy: SavedMessagesRepository {
  private let clientProxy: @Sendable () async -> ClientProxy?

  public init(authentication: MatrixAuthenticationRepository) {
    clientProxy = { await authentication.clientProxy }
  }

  public func savedRefs() async -> [SavedRef] {
    guard let client = await clientProxy()?.client,
      let json = try? await client.accountData(eventType: SavedMessages.accountDataType)
    else { return [] }
    return SavedMessages.refs(fromJSON: Data(json.utf8))
  }

  public func setSaved(_ saved: Bool, roomId: String, eventId: String) async throws(TimelineError) {
    guard let client = await clientProxy()?.client else { throw .notSignedIn }
    let refs = SavedMessages.with(
      await savedRefs(), roomId: roomId, eventId: eventId, saved: saved)
    guard let data = SavedMessages.json(refs), let content = String(data: data, encoding: .utf8)
    else { throw .requestFailed }
    do {
      try await client.setAccountData(eventType: SavedMessages.accountDataType, content: content)
    } catch {
      DebugLog.failure("setSavedMessages", error)
      throw .requestFailed
    }
  }

  /// Loads the previews eight at a time (each may ask the server), keeping the saved order.
  public func savedMessages() async -> [SavedMessage] {
    guard let client = await clientProxy()?.client else { return [] }
    let refs = await savedRefs()
    var result: [SavedMessage?] = Array(repeating: nil, count: refs.count)
    for chunk in stride(from: 0, to: refs.count, by: 8) {
      await withTaskGroup(of: (Int, SavedMessage?).self) { group in
        for index in chunk..<min(chunk + 8, refs.count) {
          let ref = refs[index]
          group.addTask { (index, await Self.message(for: ref, client: client)) }
        }
        for await (index, message) in group { result[index] = message }
      }
    }
    return result.compactMap { $0 }
  }

  /// One saved message with its preview; `nil` when its room is unknown here.
  private static func message(for ref: SavedRef, client: Client) async -> SavedMessage? {
    guard let room = try? client.getRoom(roomId: ref.roomId) else { return nil }
    let roomName = room.displayName() ?? ref.roomId
    guard let event = try? await room.loadOrFetchEvent(eventId: ref.eventId) else {
      return SavedMessage(ref: ref, roomName: roomName, senderName: nil, text: nil, date: nil)
    }
    var text: String?
    if case .messageLike(let content)? = try? event.content() {
      text = NotificationContentProxy.body(of: content)
    }
    let sender = event.senderId()
    let name =
      ((try? await room.memberDisplayName(userId: sender)) ?? nil)
      .flatMap { $0.isEmpty ? nil : $0 } ?? sender
    return SavedMessage(
      ref: ref, roomName: roomName, senderName: name, text: text,
      date: Date(timeIntervalSince1970: TimeInterval(event.timestamp()) / 1000))
  }
}
