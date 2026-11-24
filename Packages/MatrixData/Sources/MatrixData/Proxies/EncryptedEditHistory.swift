import Domain
import Foundation
import MatrixRustSDK

/// The edit history of a message in an encrypted room, read on the device. The pinned SDK has no relations API, so the
/// edits' ids come from `/relations/{eventId}/m.replace`, whose relation the server keeps in clear; each edit, and the
/// original, is then read through the SDK's event cache, which decrypts it (`Room.loadOrFetchEvent`). Nothing decrypted
/// leaves the device and nothing here logs: the text is the user's.
enum EncryptedEditHistory {
  /// As many edits as the unencrypted history asks for.
  static let limit = 50

  /// The versions, the original first; `nil` when the relations cannot be read or the original cannot be decrypted.
  static func versions(of eventId: String, roomId: String, room: Room, client: Client) async
    -> [MessageVersion]?
  {
    let path =
      "rooms/\(ClientServerRequest.encode(roomId))/relations/\(ClientServerRequest.encode(eventId))"
      + "/m.replace?limit=\(limit)"
    guard let request = ClientServerRequest.make(client: client, path: path, version: "v1"),
      let relations = await ClientServerRequest.object(request),
      let original = await decrypted(eventId, in: room)
    else { return nil }
    let edits = await withTaskGroup(of: MessageVersion.Decrypted?.self) { group in
      for id in MessageVersion.editIds(inRelations: relations) {
        group.addTask { await decrypted(id, in: room) }
      }
      var found: [MessageVersion.Decrypted] = []
      for await edit in group {
        if let edit { found.append(edit) }
      }
      return found
    }
    return MessageVersion.versions(original: original, edits: edits)
  }

  /// One event as the SDK decrypts it; `nil` when it is not a message or could not be decrypted.
  private static func decrypted(_ eventId: String, in room: Room) async
    -> MessageVersion.Decrypted?
  {
    guard let event = try? await room.loadOrFetchEvent(eventId: eventId),
      case .messageLike(.roomMessage(let type, _)) = try? event.content()
    else { return nil }
    return MessageVersion.Decrypted(
      id: event.eventId(), senderId: event.senderId(),
      body: NotificationContentProxy.body(of: type),
      date: Date(timeIntervalSince1970: Double(event.timestamp()) / 1000))
  }
}
