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
      lastMessageKind: base.lastMessageKind, isLastMessageOwn: base.isLastMessageOwn,
      lastMessageSendState: base.lastMessageSendState,
      unreadCount: Int(clamping: info.numUnreadMessages), isMarkedUnread: info.isMarkedUnread,
      mentionCount: Int(clamping: info.numUnreadMentions), avatar: avatar(of: info),
      isInvite: room.membership() == .invited, isFavourite: info.isFavourite,
      isDirect: info.isDirect, isMuted: info.cachedUserDefinedNotificationMode == .mute,
      isArchived: room.membership() == .left, isSpace: info.isSpace,
      isLowPriority: info.isLowPriority,
      draft: (try? await room.loadComposerDraft(threadRoot: nil))?.plainText
        .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
      isBroadcast: !info.isDirect && !info.isSpace
        && (info.powerLevels?.values().eventsDefault ?? 0) >= 50,
      isEncrypted: info.encryptionState == .encrypted,
      directUserId: info.isDirect && info.heroes.count == 1 ? info.heroes[0].userId : nil,
      isPublic: info.isPublic ?? false)
  }

  /// - Name: the display name, or the room id when the room has none.
  /// - Message: what the last message is and its text (`message(of:)`); none for any other latest event.
  /// - Sender: the sender's display name when the profile is loaded, otherwise the sender's Matrix id.
  /// - Own: a local event (still in the send queue) is always the user's; its state is the queue's.
  /// - Date: the event's timestamp, which the SDK gives in milliseconds since 1970.
  static func summary(id: String, displayName: String?, latestEvent: LatestEventValue)
    -> RoomSummary
  {
    let name = displayName.flatMap { $0.isEmpty ? nil : $0 } ?? id
    switch latestEvent {
    case .none:
      return RoomSummary(
        id: id, name: name, lastMessageText: nil, lastMessageSender: nil, lastActivity: nil)
    case .remote(let timestamp, let sender, let isOwn, let profile, let content):
      let message = message(of: content)
      return RoomSummary(
        id: id, name: name, lastMessageText: message?.text,
        lastMessageSender: senderName(sender, profile), lastActivity: date(timestamp),
        lastMessageKind: message?.kind, isLastMessageOwn: isOwn,
        lastMessageSendState: isOwn ? .sent : nil)
    case .local(let timestamp, let sender, let profile, let content, let state):
      let message = message(of: content)
      return RoomSummary(
        id: id, name: name, lastMessageText: message?.text,
        lastMessageSender: senderName(sender, profile), lastActivity: date(timestamp),
        lastMessageKind: message?.kind, isLastMessageOwn: true,
        lastMessageSendState: sendState(state))
    case .remoteInvite(let timestamp, _, _):
      return RoomSummary(
        id: id, name: name, lastMessageText: nil, lastMessageSender: nil,
        lastActivity: date(timestamp))
    }
  }

  static func sendState(_ state: LatestEventValueLocalState) -> RoomSummary.SendState {
    switch state {
    case .isSending: .sending
    case .hasBeenSent: .sent
    case .cannotBeSent: .failed
    }
  }

  /// What a message-like event is and the text the row shows with it; `nil` for any other event.
  static func message(of content: TimelineItemContent) -> (
    kind: RoomSummary.MessageKind, text: String?
  )? {
    guard case .msgLike(let msgLike) = content else { return nil }
    guard let message = message(ofKind: msgLike.kind) else { return nil }
    // A reply sent by an older client starts with the quoted message (the spec's reply fallback), which Flutter and the
    // web leave out of the row.
    // The SDK does not always name the replied-to event (seen on a row that showed "> <@user:server> …"), so a body
    // that opens with the fallback's own first line is treated the same.
    guard let text = message.text, msgLike.inReplyTo != nil || opensWithReplyFallback(text) else {
      return message
    }
    return (message.kind, withoutReplyFallback(text))
  }

  /// The body opens as the spec's reply fallback does: a quote line naming the sender, "> <@user:server> …".
  static func opensWithReplyFallback(_ body: String) -> Bool {
    body.hasPrefix("> <@") && body.prefix(while: { $0 != "\n" }).contains(/^> <@[^\s>]+:[^\s>]+>/)
  }

  /// The body of a reply without its fallback: the leading "> " lines and the empty line after them. A body that is
  /// nothing but the fallback stays as it is.
  static func withoutReplyFallback(_ body: String) -> String {
    var lines = body.split(separator: "\n", omittingEmptySubsequences: false)[...]
    guard lines.first?.hasPrefix("> ") == true else { return body }
    while let first = lines.first, first.hasPrefix(">") { lines = lines.dropFirst() }
    if lines.first?.isEmpty == true { lines = lines.dropFirst() }
    let rest = lines.joined(separator: "\n")
    return rest.isEmpty ? body : rest
  }

  /// The body of a text, the caption of a picture or a video, the name of a file and the question of a poll; never
  /// the body of an event that could not be decrypted (web `roomRowText.ts`).
  static func message(ofKind kind: MsgLikeKind) -> (kind: RoomSummary.MessageKind, text: String?)? {
    switch kind {
    case .message(let content):
      return switch content.msgType {
      case .text(let text): (.text, text.body)
      case .emote(let emote): (.emote, emote.body)
      case .notice(let notice): (.notice, notice.body)
      case .image(let image): (.picture, image.caption?.nilIfEmpty)
      case .gallery(let gallery): (.picture, gallery.body.nilIfEmpty)
      case .video(let video): (.video, video.caption?.nilIfEmpty)
      case .audio(let audio): (audio.voice == nil ? .audio : .voice, nil)
      case .file(let file): (.file, file.filename.nilIfEmpty)
      case .location: (.location, nil)
      case .other(_, let body): (.text, body)
      }
    case .sticker: return (.sticker, nil)
    case .poll(let question, _, _, _, _, _, _): return (.poll, question.nilIfEmpty)
    case .redacted: return (.deleted, nil)
    case .unableToDecrypt: return (.encrypted, nil)
    case .liveLocation: return (.location, nil)
    case .other: return nil
    }
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

extension String {
  fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
