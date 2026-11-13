import Domain
import Foundation
import MatrixRustSDK

/// Builds Domain `TimelineItem` values from SDK timeline items (ADR 0006). Room events become the one-line notices of
/// the Flutter app (`assets/l10n/intl_en.arb`: joinedTheChat, userLeftTheChat, …). Nothing here logs: items hold
/// message content (ADR 0009).
enum TimelineItemMapper {
  /// `nil` for an SDK item the room screen does not show. `ownUserId` tells which reactions the user sent.
  static func item(_ item: MatrixRustSDK.TimelineItem, ownUserId: String?) -> Domain.TimelineItem? {
    let id = item.uniqueId().id
    if let virtual = item.asVirtual() {
      switch virtual {
      case .dateDivider(let ts): return .init(id: id, kind: .dayDivider(date(ts)))
      case .readMarker: return .init(id: id, kind: .readMarker)
      case .timelineStart: return .init(id: id, kind: .timelineStart)
      @unknown default: return nil
      }
    }
    guard let event = item.asEvent() else { return nil }
    let sender = name(event.sender, event.senderProfile)
    switch event.content {
    case .msgLike(let content):
      return .init(
        id: id, kind: .message(message(event, content, sender: sender, ownUserId: ownUserId)))
    case .roomMembership(let userId, let userDisplayName, let change, _):
      let target = userDisplayName.flatMap { $0.isEmpty ? nil : $0 } ?? userId
      return membership(change, sender: sender, target: target).map {
        .init(id: id, kind: .stateNotice($0))
      }
    case .profileChange(let displayName, let previous, let avatar, let previousAvatar):
      if let displayName, displayName != previous {
        return .init(
          id: id,
          kind: .stateNotice("\(previous ?? sender) changed their displayname to: '\(displayName)'")
        )
      }
      if avatar != previousAvatar {
        return .init(id: id, kind: .stateNotice("\(sender) changed their avatar"))
      }
      return nil
    case .state(_, let content):
      return state(content, sender: sender).map { .init(id: id, kind: .stateNotice($0)) }
    default:
      return nil
    }
  }

  private static func message(
    _ event: EventTimelineItem, _ content: MsgLikeContent, sender: String, ownUserId: String?
  ) -> TimelineMessage {
    let eventId: String? =
      if case .eventId(let value) = event.eventOrTransactionId { value } else { nil }
    var isEdited = false
    var media: MediaReference?
    let body: TimelineMessage.Body
    switch content.kind {
    case .message(let message):
      isEdited = message.isEdited
      body = Self.body(message.msgType)
      media = Self.media(message.msgType)
    case .sticker(let text, let info, let source):
      body = .sticker(text)
      media = reference(
        source, info.thumbnailSource, info.mimetype, info.size, info.width, info.height)
    case .poll(let question, _, _, _, _, _, _): body = .poll(question: question)
    case .redacted: body = .redacted
    case .unableToDecrypt: body = .unableToDecrypt
    default: body = .unsupported
    }
    let reactions = content.reactions.map { reaction in
      TimelineMessage.Reaction(
        key: reaction.key, count: reaction.senders.count,
        includesOwn: reaction.senders.contains { $0.senderId == ownUserId })
    }
    return TimelineMessage(
      eventId: eventId, senderId: event.sender, senderName: sender, isOwn: event.isOwn,
      date: date(event.timestamp), body: body, isEdited: isEdited, reactions: reactions,
      reply: content.inReplyTo.map(reply), sendState: sendState(event.localSendState), media: media)
  }

  static func body(_ type: MessageType) -> TimelineMessage.Body {
    switch type {
    case .text(let content): .text(content.body)
    case .emote(let content): .emote(content.body)
    case .notice(let content): .notice(content.body)
    case .image(let content): .image(caption: content.caption)
    case .video(let content): .video(caption: content.caption)
    case .audio(let content): .audio(caption: content.caption)
    case .file(let content): .file(name: content.filename)
    case .location(let content): .location(content.body)
    case .other(_, let body): .text(body)
    default: .unsupported
    }
  }

  /// The media of a picture, video, voice message or file; `nil` for the other message types.
  static func media(_ type: MessageType) -> MediaReference? {
    switch type {
    case .image(let content):
      let info = content.info
      return reference(
        content.source, info?.thumbnailSource, info?.mimetype, info?.size, info?.width, info?.height
      )
    case .video(let content):
      let info = content.info
      return reference(
        content.source, info?.thumbnailSource, info?.mimetype, info?.size, info?.width, info?.height
      )
    case .audio(let content):
      return reference(content.source, nil, content.info?.mimetype, content.info?.size, nil, nil)
    case .file(let content):
      let info = content.info
      return reference(content.source, info?.thumbnailSource, info?.mimetype, info?.size, nil, nil)
    default:
      return nil
    }
  }

  private static func reference(
    _ source: MediaSource, _ thumbnail: MediaSource?, _ mimeType: String?, _ size: UInt64?,
    _ width: UInt64?,
    _ height: UInt64?
  ) -> MediaReference {
    MediaReference(
      source: source.toJson(), thumbnailSource: thumbnail?.toJson(), mimeType: mimeType,
      size: size.map { Int(clamping: $0) }, width: width.map { Int(clamping: $0) },
      height: height.map { Int(clamping: $0) })
  }

  private static func reply(_ details: InReplyToDetails) -> TimelineMessage.Reply {
    switch details.event() {
    case .ready(let content, let sender, let profile, _, _):
      var text: String?
      if case .msgLike(let msgLike) = content {
        switch msgLike.kind {
        case .message(let message): text = preview(body(message.msgType))
        case .sticker(let body, _, _): text = body
        case .poll(let question, _, _, _, _, _, _): text = question
        case .redacted: text = "This message has been deleted"
        case .unableToDecrypt: text = "This message has been encrypted"
        default: text = nil
        }
      }
      return .init(senderName: name(sender, profile), text: text)
    default:
      return .init(senderName: "", text: nil)
    }
  }

  /// One line for a message body, as reply previews show it.
  static func preview(_ body: TimelineMessage.Body) -> String {
    switch body {
    case .text(let text), .emote(let text), .notice(let text), .location(let text),
      .sticker(let text):
      text
    case .image(let caption): caption ?? "🖼️ Picture"
    case .video(let caption): caption ?? "🎥 Video"
    case .audio(let caption): caption ?? "🎤 Audio"
    case .file(let name): "📁 \(name)"
    case .poll(let question): question
    case .redacted: "This message has been deleted"
    case .unableToDecrypt: "This message has been encrypted"
    case .unsupported: "Unknown event"
    }
  }

  private static func membership(_ change: MembershipChange?, sender: String, target: String)
    -> String?
  {
    switch change {
    case .joined: "👋 \(target) joined the chat"
    case .left: "🚪 \(target) left the chat"
    case .banned, .kickedAndBanned: "🚫 \(sender) banned \(target)"
    case .unbanned: "\(sender) unbanned \(target)"
    case .kicked: "👞 \(sender) kicked \(target)"
    case .invited: "📩 \(sender) invited \(target)"
    case .invitationAccepted: "👍 \(target) accepted the invitation"
    case .invitationRejected: "\(target) rejected the invitation"
    default: nil
    }
  }

  private static func state(_ content: OtherState, sender: String) -> String? {
    switch content {
    case .roomCreate: "💬 \(sender) created the chat"
    case .roomEncryption: "🔐 \(sender) activated end to end encryption"
    case .roomName(let name?): "\(sender) changed the chat name to: '\(name)'"
    case .roomTopic(let topic?): "\(sender) changed the chat description to: '\(topic)'"
    case .roomAvatar: "\(sender) changed the chat avatar"
    default: nil
    }
  }

  static func name(_ userId: String, _ profile: ProfileDetails) -> String {
    if case .ready(let displayName?, _, _) = profile, !displayName.isEmpty { return displayName }
    return userId
  }

  private static func sendState(_ state: EventSendState?) -> TimelineMessage.SendState {
    switch state {
    case nil, .sent: .sent
    case .notSentYet: .sending
    case .sendingFailed: .failed
    @unknown default: .sent
    }
  }

  private static func date(_ timestamp: Timestamp) -> Date {
    Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
  }
}
