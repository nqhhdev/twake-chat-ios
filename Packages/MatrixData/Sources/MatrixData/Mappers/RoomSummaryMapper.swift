import Domain
import Foundation
import MatrixRustSDK

/// Builds the Domain `RoomSummary` from an SDK room (ADR 0006). Nothing here logs: the summary holds message content
/// (ADR 0009).
enum RoomSummaryMapper {
  /// Reads the room's id, display name, latest event and unread counts.
  static func summary(for room: Room) async -> RoomSummary {
    let base = summary(
      id: room.id(), displayName: room.displayName(), latestEvent: await room.latestEvent())
    guard let info = try? await room.roomInfo() else { return base }
    return RoomSummary(
      id: base.id, name: base.name, lastMessageText: base.lastMessageText,
      lastMessageSender: base.lastMessageSender, lastActivity: base.lastActivity,
      unreadCount: Int(clamping: max(info.numUnreadMessages, info.isMarkedUnread ? 1 : 0)),
      mentionCount: Int(clamping: info.numUnreadMentions), avatar: avatar(of: info),
      isInvite: room.membership() == .invited, isFavourite: info.isFavourite,
      isDirect: info.isDirect, isMuted: info.cachedUserDefinedNotificationMode == .mute,
      isArchived: room.membership() == .left, isSpace: info.isSpace)
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

  /// The room's picture; a room without one that has a single other member (a direct chat) shows that person's, as
  /// Element X and the Flutter app do.
  static func avatar(of info: RoomInfo) -> MediaReference? {
    if let room = avatar(info.avatarUrl) { return room }
    guard info.heroes.count == 1 else { return nil }
    return avatar(info.heroes[0].avatarUrl)
  }

  /// A picture's `mxc://` URL as a media reference the media repository loads.
  static func avatar(_ url: String?) -> MediaReference? {
    guard let url, !url.isEmpty, let source = try? MediaSource.fromUrl(url: url) else { return nil }
    return MediaReference(source: source.toJson(), mimeType: "image/*")
  }

  private static func date(_ timestamp: Timestamp) -> Date {
    Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
  }
}
