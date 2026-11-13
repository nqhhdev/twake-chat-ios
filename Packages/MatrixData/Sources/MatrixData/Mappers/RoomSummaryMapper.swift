import Domain
import Foundation
import MatrixRustSDK

/// Builds the Domain `RoomSummary` from an SDK room (ADR 0006). Nothing here logs: the summary holds message content
/// (ADR 0009).
enum RoomSummaryMapper {
  /// Reads the room's id, display name and latest event.
  static func summary(for room: Room) async -> RoomSummary {
    summary(id: room.id(), displayName: room.displayName(), latestEvent: await room.latestEvent())
  }

  /// - Name: the display name, or the room id when the room has none.
  /// - Text: the body of a message (`m.room.message`); `nil` for any other latest event.
  /// - Sender: the sender's display name when the profile is loaded, otherwise the sender's Matrix id.
  /// - Date: the event's timestamp, which the SDK gives in milliseconds since 1970.
  static func summary(id: String, displayName: String?, latestEvent: LatestEventValue)
    -> RoomSummary
  {
    let name = displayName.flatMap { $0.isEmpty ? nil : $0 } ?? id
    switch latestEvent {
    case .none:
      return RoomSummary(
        id: id, name: name, lastMessageText: nil, lastMessageSender: nil, lastActivity: nil)
    case .remote(let timestamp, let sender, _, let profile, let content),
      .local(let timestamp, let sender, let profile, let content, _):
      return RoomSummary(
        id: id, name: name, lastMessageText: text(of: content),
        lastMessageSender: senderName(sender, profile), lastActivity: date(timestamp))
    case .remoteInvite(let timestamp, _, _):
      return RoomSummary(
        id: id, name: name, lastMessageText: nil, lastMessageSender: nil,
        lastActivity: date(timestamp))
    }
  }

  private static func text(of content: TimelineItemContent) -> String? {
    guard case .msgLike(let msgLike) = content, case .message(let message) = msgLike.kind else {
      return nil
    }
    return message.body
  }

  private static func senderName(_ sender: String, _ profile: ProfileDetails) -> String {
    if case .ready(let displayName?, _, _) = profile, !displayName.isEmpty { return displayName }
    return sender
  }

  private static func date(_ timestamp: Timestamp) -> Date {
    Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
  }
}
