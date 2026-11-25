import Domain

extension ChatListViewModel {
  public func spaceUnread(of room: RoomSummary) -> SpaceUnread? {
    guard room.isSpace, !room.isInvite else { return nil }
    return SpaceUnread.of(room, in: allJoinedRooms)
  }
}
