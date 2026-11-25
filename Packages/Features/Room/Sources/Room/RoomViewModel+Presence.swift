import Domain
import SwiftUI

extension RoomViewModel {
  static let presenceFreshness: Duration = .seconds(60)

  func refreshPresence(of userId: String, now: ContinuousClock.Instant = .now) async {
    guard let detailsRepository else { return }
    if let fetched = presenceFetchedAt[userId], now - fetched < Self.presenceFreshness { return }
    presenceFetchedAt[userId] = now
    let dot = await detailsRepository.presence(of: userId)?.dot
    guard presenceDots[userId] != dot else { return }
    withAnimation(.easeInOut(duration: 0.15)) { presenceDots[userId] = dot }
  }

  func presenceDot(of userId: String) -> Presence.Dot? {
    presenceDots[userId]
  }
}
