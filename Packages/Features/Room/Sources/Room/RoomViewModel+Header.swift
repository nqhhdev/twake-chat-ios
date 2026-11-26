import Domain
import Foundation
import SwiftUI

extension RoomViewModel {
  public var emptyChatCard: EmptyChatCard {
    .card(
      roomName: roomName, isDirect: isDirect, isBroadcast: isBroadcast, isEncrypted: isEncrypted,
      canPost: canSendMessages)
  }

  public var headerSubtitle: String? {
    if let presenceLine { return presenceLine }
    guard let memberCount, memberCount > 0 else { return nil }
    return localized("\(memberCount) members")
  }

  public func retryDecryption() async {
    await repository.retryDecryption(sessionIds: [])
  }

  public func watchPresence(
    every interval: Duration = .seconds(15), lowPower lowPowerInterval: Duration = .seconds(60),
    isLowPower: @escaping @Sendable () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled }
  ) async {
    guard threadRootId == nil, let detailsRepository else { return }
    var waits = 0
    while !Task.isCancelled {
      guard let userId = directUserId else {
        waits += 1
        guard waits <= 10 else { return }
        try? await Task.sleep(for: .seconds(1))
        continue
      }
      let line = await detailsRepository.presence(of: userId)?.line
      if line != presenceLine {
        withAnimation(.easeInOut(duration: 0.25)) { presenceLine = line }
      }
      try? await Task.sleep(for: isLowPower() ? lowPowerInterval : interval)
    }
  }

  public var successorLink: URL? {
    successorRoomId.flatMap {
      let via =
        MatrixLink.server(of: $0).map { [$0] } ?? MatrixLink.server(of: roomId).map { [$0] } ?? []
      return MatrixLink.room(idOrAlias: $0, eventId: nil, via: via).url
    }
  }

  public func unblock() async {
    guard let userId = blockedUserId, let blocking else { return }
    if await blocking.unblock(userId) {
      withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { blockedUserId = nil }
    } else {
      errorMessage = localized("Could not unblock. Please try again.")
    }
  }

  public static func dayTitle(_ date: Date, now: Date = .now, calendar: Calendar = .current)
    -> String
  {
    if calendar.isDate(date, inSameDayAs: now) { return localized("Today") }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
      calendar.isDate(date, inSameDayAs: yesterday)
    {
      return localized("Yesterday")
    }
    return date.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
  }
}
