import Domain
import Foundation
import MatrixRustSDK

/// The archive reads the rooms the SDK store keeps with the membership "left". The Flutter app also asks the server
/// for older left rooms (`loadArchive`); the pinned SDK has no such call, so a chat left on another device before this
/// sign-in does not show.
extension RoomListProxy: ArchivedRoomsRepository {
  public func archivedRooms() async throws(Domain.RoomListError) -> [RoomSummary] {
    guard let client = await clientProxy()?.client else { throw .notSignedIn }
    var rooms: [RoomSummary] = []
    for room in client.rooms() where room.membership() == .left {
      rooms.append(await RoomSummaryMapper.summary(for: room))
    }
    // Chats left on another device, from the archive the web client keeps in the account data; a chat the user is in
    // again (rejoined elsewhere) is left out.
    let json = (try? await client.accountData(eventType: RoomArchive.accountDataType)) ?? nil
    let known = Set(rooms.map(\.id))
    for entry in RoomArchive.entries(fromJSON: json.map { Data($0.utf8) })
    where !known.contains(entry.roomId) {
      if let room = try? client.getRoom(roomId: entry.roomId), room.membership() != .left {
        continue
      }
      rooms.append(
        RoomSummary(
          id: entry.roomId, name: entry.name, lastMessageText: nil, lastMessageSender: nil,
          lastActivity: Date(timeIntervalSince1970: TimeInterval(entry.leftAt) / 1000),
          avatar: RoomSummaryMapper.avatar(entry.avatarURL), isDirect: entry.isDirect,
          isArchived: true))
    }
    // Most recent first; rooms without a date by name, so the order does not change between loads.
    return rooms.sorted { lhs, rhs in
      let left = lhs.lastActivity ?? .distantPast
      let right = rhs.lastActivity ?? .distantPast
      if left != right { return left > right }
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
  }

  public func rejoin(roomId: String) async throws(Domain.RoomListError) {
    guard let client = await clientProxy()?.client else { throw .notSignedIn }
    do { _ = try await client.joinRoomById(roomId: roomId) } catch { throw .requestFailed }
    await updateArchive(roomId: roomId, with: nil)
  }

  public func forget(roomId: String) async throws(Domain.RoomListError) {
    guard let room = try? await clientProxy()?.client.getRoom(roomId: roomId) else {
      // Only in the account data archive (left on another device): dropping it there is all there is to do.
      await updateArchive(roomId: roomId, with: nil)
      return
    }
    do { try await room.forget() } catch { throw .requestFailed }
    await updateArchive(roomId: roomId, with: nil)
  }
}
