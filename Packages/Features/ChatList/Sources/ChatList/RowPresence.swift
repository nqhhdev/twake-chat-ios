import DesignSystem
import Domain
import SwiftUI

extension ChatListViewModel {
  static let presenceFreshness: Duration = .seconds(60)

  public func refreshPresence(of room: RoomSummary, now: ContinuousClock.Instant = .now) async {
    guard room.isDirect, !room.isInvite, let userId = room.directUserId, let presence else {
      return
    }
    if let fetched = presenceFetchedAt[userId], now - fetched < Self.presenceFreshness { return }
    presenceFetchedAt[userId] = now
    let dot = await presence(userId)?.dot
    guard presenceDots[userId] != dot else { return }
    withAnimation(.easeInOut(duration: 0.15)) { presenceDots[userId] = dot }
  }

  public func presenceDot(of room: RoomSummary) -> Presence.Dot? {
    guard room.isDirect, let userId = room.directUserId else { return nil }
    return presenceDots[userId]
  }
}

extension AvatarPresence {
  init(_ dot: Presence.Dot) {
    self =
      switch dot {
      case .online: .online
      case .away: .away
      }
  }
}
