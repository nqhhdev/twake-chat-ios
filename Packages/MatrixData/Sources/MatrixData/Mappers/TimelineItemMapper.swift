import Domain
import Foundation
import MatrixRustSDK

/// Builds Domain `TimelineItem` values from SDK timeline items (ADR 0006). Room events become the one-line notices of
/// the Flutter app (`assets/l10n/intl_en.arb`: joinedTheChat, userLeftTheChat, …). Nothing here logs: items hold
/// message content (ADR 0009).
enum TimelineItemMapper {
  /// `nil` for an SDK item the room screen does not show. `ownUserId` tells which reactions the user sent.
  /// A single event as a message, for the pinned messages; `nil` when it is not message-like.
  static func message(from event: EventTimelineItem, ownUserId: String?) -> TimelineMessage? {
    guard case .msgLike(let content) = event.content else { return nil }
    return message(
      event, content, sender: name(event.sender, event.senderProfile), ownUserId: ownUserId)
  }

  private static func senderAvatar(_ profile: ProfileDetails) -> MediaReference? {
    guard case .ready(_, _, let url) = profile else { return nil }
    return RoomSummaryMapper.avatar(url)
  }

  /// A short text made only of emojis (up to three), which the room shows large.
  private static func isEmojiOnly(_ body: TimelineMessage.Body, _ event: EventTimelineItem) -> Bool
  {
    guard case .text(let text) = body, text.count <= 3 else { return false }
    return event.lazyProvider.containsOnlyEmojis()
  }

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
      return state(content, sender: sender).map {
        .init(id: id, kind: .stateNotice($0.text), visibility: $0.visibility)
      }
    case .failedToParseMessageLike(let eventType, _), .failedToParseState(let eventType, _, _):
      return .init(id: id, kind: .stateNotice(unknown(eventType)), visibility: .unknown)
    default:
      return nil
    }
  }

  private static func message(
    _ event: EventTimelineItem, _ content: MsgLikeContent, sender: String, ownUserId: String?
  ) -> TimelineMessage {
    let eventId: String? =
      if case .eventId(let value) = event.eventOrTransactionId { value } else { nil }
    let transactionId: String? =
      if case .transactionId(let value) = event.eventOrTransactionId { value } else { nil }
    var isEdited = false
    var media: MediaReference?
    var formatted: AttributedString?
    var poll: Domain.Poll?
    let body: TimelineMessage.Body
    switch content.kind {
    case .message(let message):
      isEdited = message.isEdited
      body = Self.body(message.msgType)
      media = Self.media(message.msgType)
      formatted = Self.formatted(message.msgType)
    case .sticker(let text, let info, let source):
      body = .sticker(text)
      media = reference(
        source, info.thumbnailSource, info.mimetype, info.size, info.width, info.height)
    case .poll(
      let question, let kind, let maxSelections, let answers, let votes, let endTime, let edited):
      body = .poll(question: question)
      isEdited = edited
      poll = Self.poll(
        question: question, isDisclosed: kind == .disclosed, maxSelections: maxSelections,
        answers: answers.map { ($0.id, $0.text) }, votes: votes, isEnded: endTime != nil,
        ownUserId: ownUserId)
    case .redacted: body = .redacted
    case .unableToDecrypt(let encrypted): body = .unableToDecrypt(undecryptableReason(encrypted))
    default: body = .unsupported
    }
    let reactions = content.reactions.map { reaction in
      TimelineMessage.Reaction(
        key: reaction.key, count: reaction.senders.count,
        includesOwn: reaction.senders.contains { $0.senderId == ownUserId },
        senderIds: reaction.senders.sorted { $0.timestamp < $1.timestamp }.map(\.senderId))
    }
    return TimelineMessage(
      eventId: eventId, senderId: event.sender, senderName: sender, isOwn: event.isOwn,
      date: date(event.timestamp), body: body, isEdited: isEdited, reactions: reactions,
      reply: content.inReplyTo.map(reply), sendState: sendState(event.localSendState), media: media,
      isEmojiOnly: isEmojiOnly(body, event), senderAvatar: senderAvatar(event.senderProfile),
      readCount: event.readReceipts.keys.filter { $0 != ownUserId }.count,
      readerIds: event.readReceipts.keys.filter { $0 != ownUserId }.sorted(),
      replyToEventId: content.inReplyTo?.eventId(), formatted: formatted,
      uploadProgress: uploadProgress(event.localSendState), poll: poll,
      thread: content.threadSummary.map(thread), threadRootId: content.threadRoot,
      batchId: batchId(body, event), transactionId: transactionId)
  }

  /// The album key of a picture (`MediaBatch`), read from the event's original JSON; only pictures form albums, so
  /// other messages skip the parse.
  private static func batchId(_ body: TimelineMessage.Body, _ event: EventTimelineItem) -> String? {
    guard case .image = body else { return nil }
    return MediaBatch.id(inOriginalJSON: event.lazyProvider.debugInfo().originalJson)
  }

  private static func thread(_ summary: ThreadSummary) -> TimelineMessage.ThreadPreview {
    let latest = embedded(summary.latestEvent())
    return .init(
      replyCount: Int(clamping: summary.numReplies()), latestSenderName: latest?.senderName,
      latestText: latest?.text)
  }

  /// A poll's answers with their voters, as the SDK counts the votes (answer id → voters).
  static func poll(
    question: String, isDisclosed: Bool, maxSelections: UInt64,
    answers: [(id: String, text: String)],
    votes: [String: [String]], isEnded: Bool, ownUserId: String?
  ) -> Domain.Poll {
    let own = Set(votes.filter { $0.value.contains { $0 == ownUserId } }.map(\.key))
    return Domain.Poll(
      question: question,
      answers: answers.map { .init(id: $0.id, text: $0.text, voterIds: votes[$0.id] ?? []) },
      maxSelections: Int(clamping: maxSelections), isDisclosed: isDisclosed, isEnded: isEnded,
      ownAnswerIds: own)
  }

  /// The share of a media upload done, from the send queue's local echo; `nil` when nothing is uploading.
  static func uploadProgress(_ state: EventSendState?) -> Double? {
    guard case .notSentYet(let progress?) = state, progress.progress.total > 0 else { return nil }
    return min(1, Double(progress.progress.current) / Double(progress.progress.total))
  }

  /// The HTML body of a text, emote or notice as styled text, as the web client renders it; `nil` without one.
  static func formatted(_ type: MessageType) -> AttributedString? {
    let formatted: FormattedBody? =
      switch type {
      case .text(let content): content.formatted
      case .emote(let content): content.formatted
      case .notice(let content): content.formatted
      default: nil
      }
    guard let formatted, case .html = formatted.format, !formatted.body.isEmpty else { return nil }
    let rendered = MatrixHTML.attributedString(from: formatted.body)
    return rendered.characters.isEmpty ? nil : rendered
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
    case .location(let content): .location(content.body, place: GeoPoint(geoUri: content.geoUri))
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
        content.source, info?.thumbnailSource, info?.mimetype, info?.size, info?.width,
        info?.height,
        blurhash: info?.blurhash)
    case .video(let content):
      let info = content.info
      return reference(
        content.source, info?.thumbnailSource, info?.mimetype, info?.size, info?.width,
        info?.height,
        blurhash: info?.blurhash)
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
    _ height: UInt64?, blurhash: String? = nil
  ) -> MediaReference {
    MediaReference(
      source: source.toJson(), thumbnailSource: thumbnail?.toJson(), mimeType: mimeType,
      size: size.map { Int(clamping: $0) }, width: width.map { Int(clamping: $0) },
      height: height.map { Int(clamping: $0) }, blurhash: blurhash.flatMap { $0.isEmpty ? nil : $0 }
    )
  }

  private static func reply(_ details: InReplyToDetails) -> TimelineMessage.Reply {
    embedded(details.event()) ?? .init(senderName: "", text: nil)
  }

  /// The sender and one line of an event another one points at (a reply's original, a thread's latest reply), or
  /// `nil` while it is not loaded.
  private static func embedded(_ details: EmbeddedEventDetails) -> TimelineMessage.Reply? {
    switch details {
    case .ready(let content, let sender, let profile, _, _):
      let text = line(of: content)
      return .init(senderName: name(sender, profile), text: text)
    default:
      return nil
    }
  }

  /// One line for an event's content, as a reply preview or a thread list shows it; `nil` for content that has none.
  static func line(of content: TimelineItemContent) -> String? {
    var text: String?
    if case .msgLike(let msgLike) = content {
      switch msgLike.kind {
      case .message(let message): text = preview(body(message.msgType))
      case .sticker(let body, _, _): text = body
      case .poll(let question, _, _, _, _, _, _): text = question
      case .redacted: text = "This message has been deleted"
      case .unableToDecrypt: text = "Waiting for this message"
      default: text = nil
      }
    }
    return text
  }

  /// One line for a message body, as reply previews show it.
  static func preview(_ body: TimelineMessage.Body) -> String {
    switch body {
    case .text(let text), .emote(let text), .notice(let text), .location(let text, _),
      .sticker(let text):
      text
    case .image(let caption): caption ?? "🖼️ Picture"
    case .video(let caption): caption ?? "🎥 Video"
    case .audio(let caption): caption ?? "🎤 Audio"
    case .file(let name): "📁 \(name)"
    case .poll(let question): question
    case .redacted: "This message has been deleted"
    case .unableToDecrypt: "Waiting for this message"
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

  /// A room state event as a notice, and which chat setting can hide it (Flutter `EventTypeRules`): the room's name,
  /// picture and creation always show; its settings are unimportant; pinned messages, aliases and server rules never
  /// show; any other kind is unknown.
  static func state(_ content: OtherState, sender: String) -> (
    text: String, visibility: Domain.TimelineItem.Visibility
  )? {
    switch content {
    case .roomCreate: ("💬 \(sender) created the chat", .always)
    case .roomName(let name?): ("\(sender) changed the chat name to: '\(name)'", .always)
    case .roomAvatar: ("\(sender) changed the chat avatar", .always)
    case .roomEncryption: ("🔐 \(sender) activated end to end encryption", .unimportant)
    case .roomTopic(let topic?):
      ("\(sender) changed the chat description to: '\(topic)'", .unimportant)
    case .roomTopic(nil): ("\(sender) removed the chat description", .unimportant)
    case .roomJoinRules(let rule):
      (joinRuleText(rule, sender: sender), .unimportant)
    case .roomHistoryVisibility(let visibility):
      ("\(sender) changed the history visibility to: \(historyText(visibility))", .unimportant)
    case .roomGuestAccess: ("\(sender) changed the guest access rules", .unimportant)
    case .roomPowerLevels: ("\(sender) changed the chat permissions", .unimportant)
    case .roomName(nil), .roomCanonicalAlias, .roomPinnedEvents, .roomServerAcl: nil
    case .policyRuleRoom: (unknown("m.policy.rule.room"), .unknown)
    case .policyRuleServer: (unknown("m.policy.rule.server"), .unknown)
    case .policyRuleUser: (unknown("m.policy.rule.user"), .unknown)
    case .roomAliases: (unknown("m.room.aliases"), .unknown)
    case .roomThirdPartyInvite: (unknown("m.room.third_party_invite"), .unknown)
    case .roomTombstone: ("This chat has been upgraded", .always)
    case .spaceChild: (unknown("m.space.child"), .unknown)
    case .spaceParent: (unknown("m.space.parent"), .unknown)
    case .custom(let eventType): (unknown(eventType), .unknown)
    }
  }

  /// The Flutter app's line for an event it cannot show (`unknownEvent`).
  static func unknown(_ eventType: String) -> String { "Unknown event '\(eventType)'" }

  private static func joinRuleText(_ rule: JoinRule?, sender: String) -> String {
    let name: String? =
      switch rule {
      case .public: "Anyone can join"
      case .invite: "Invited users only"
      case .knock: "Anyone can ask to join"
      default: nil
      }
    guard let name else { return "\(sender) changed the join rules" }
    return "\(sender) changed the join rules to: \(name)"
  }

  private static func historyText(_ visibility: HistoryVisibility) -> String {
    switch visibility {
    case .invited: "From the invitation"
    case .joined: "From joining"
    case .shared: "Visible for all participants"
    default: "Visible for everyone"
    }
  }

  static func name(_ userId: String, _ profile: ProfileDetails) -> String {
    if case .ready(let displayName?, _, _) = profile, !displayName.isEmpty { return displayName }
    return userId
  }

  /// Why the SDK could not decrypt the message; only a Megolm message carries a cause.
  static func undecryptableReason(_ message: EncryptedMessage) -> UndecryptableReason {
    guard case .megolmV1AesSha2(_, let cause) = message else { return .unknown }
    return switch cause {
    case .sentBeforeWeJoined: .sentBeforeJoining
    case .withheldBySender, .withheldForUnverifiedOrInsecureDevice: .withheld
    case .verificationViolation, .unsignedDevice, .unknownDevice: .untrustedSender
    case .historicalMessageAndBackupIsDisabled: .historical
    case .historicalMessageAndDeviceIsUnverified: .historicalUnverified
    case .unknown: .unknown
    }
  }

  private static func sendState(_ state: EventSendState?) -> TimelineMessage.SendState {
    switch state {
    case nil, .sent: .sent
    case .notSentYet: .sending
    case .sendingFailed: .failed
    @unknown default: .sent
    }
  }

  static func date(_ timestamp: Timestamp) -> Date {
    Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
  }
}

extension TimelineItemMapper {
  /// A thread of the room's thread list (`ThreadListService`).
  static func threadEntry(_ item: ThreadListItem) -> ThreadListEntry {
    let root = item.rootEvent
    let latest = item.latestEvent
    return ThreadListEntry(
      rootEventId: root.eventId, rootSenderName: name(root.sender, root.senderProfile),
      rootText: root.content.flatMap(line(of:)), date: date(root.timestamp),
      replyCount: Int(item.numReplies),
      latestSenderName: latest.map { name($0.sender, $0.senderProfile) },
      latestText: latest?.content.flatMap(line(of:)), latestDate: latest.map { date($0.timestamp) })
  }
}
