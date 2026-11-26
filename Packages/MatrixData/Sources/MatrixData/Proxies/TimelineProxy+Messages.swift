import Domain
import Foundation
import MatrixRustSDK

extension TimelineProxy {
  public func reply(text: String, to eventId: String) async throws(TimelineError) {
    let timeline = try openedTimeline()
    do {
      try await timeline.sendReply(msg: Self.content(text, emotes: knownEmotes), eventId: eventId)
    } catch {
      throw Self.failure("reply", error)
    }
  }

  public func edit(eventId: String, text: String) async throws(TimelineError) {
    let timeline = try openedTimeline()
    do {
      try await timeline.edit(
        eventOrTransactionId: .eventId(eventId: eventId),
        newContent: .roomMessage(content: Self.content(text, emotes: knownEmotes)))
    } catch {
      throw Self.failure("edit", error)
    }
  }

  public func redact(eventId: String) async throws(TimelineError) {
    let timeline = try openedTimeline()
    do {
      try await timeline.redactEvent(eventOrTransactionId: .eventId(eventId: eventId), reason: nil)
    } catch {
      throw Self.failure("redact", error)
    }
  }

  public func toggleReaction(_ key: String, on eventId: String) async throws(TimelineError) {
    let timeline = try openedTimeline()
    do {
      _ = try await timeline.toggleReaction(itemId: .eventId(eventId: eventId), key: key)
    } catch {
      throw Self.failure("toggleReaction", error)
    }
  }

  public func setPinned(_ pinned: Bool, eventId: String) async throws(TimelineError) {
    let timeline = try openedTimeline()
    do {
      _ =
        pinned
        ? try await timeline.pinEvent(eventId: eventId)
        : try await timeline.unpinEvent(eventId: eventId)
    } catch {
      throw Self.failure("setPinned", error)
    }
  }

  public func pinnedMessages() async -> [TimelineMessage] {
    guard let opened, let info = try? await opened.room.roomInfo() else { return [] }
    let ownUserId = try? opened.client.userId
    var messages: [TimelineMessage] = []
    for eventId in info.pinnedEventIds {
      if let event = try? await opened.timeline.getEventTimelineItemByEventId(eventId: eventId) {
        if let message = TimelineItemMapper.message(from: event, ownUserId: ownUserId) {
          messages.append(message)
        }
      } else if let event = try? await opened.room.loadOrFetchEvent(eventId: eventId),
        let message = Self.pinnedMessage(from: event, ownUserId: ownUserId)
      {
        messages.append(message)
      }
    }
    return messages
  }

  static func pinnedMessage(from event: TimelineEvent, ownUserId: String?) -> TimelineMessage? {
    guard case .messageLike(let content)? = try? event.content(),
      let text = NotificationContentProxy.body(of: content)
    else { return nil }
    let senderId = event.senderId()
    return TimelineMessage(
      eventId: event.eventId(), senderId: senderId, senderName: senderId,
      isOwn: senderId == ownUserId, date: TimelineItemMapper.date(event.timestamp()),
      body: .text(text))
  }

  public func forward(eventId: String, to roomId: String) async throws(TimelineError) {
    let opened = try openedState()
    guard let target = try? opened.client.client.getRoom(roomId: roomId) else {
      throw .roomNotFound
    }
    do {
      let event = try await opened.timeline.getEventTimelineItemByEventId(eventId: eventId)
      guard let json = event.lazyProvider.debugInfo().originalJson,
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
        let type = object["type"] as? String, var content = object["content"] as? [String: Any]
      else { throw TimelineError.requestFailed }
      content["m.relates_to"] = nil
      content["m.new_content"] = nil
      MediaBatch.remove(from: &content)
      let body = try JSONSerialization.data(withJSONObject: content)
      try await target.sendRaw(eventType: type, content: String(decoding: body, as: UTF8.self))
    } catch {
      throw Self.failure("forward", error)
    }
  }

  public func loadDraft() async -> String? {
    guard let draft = try? await opened?.room.loadComposerDraft(threadRoot: threadRoot) else {
      return nil
    }
    return draft.plainText.isEmpty ? nil : draft.plainText
  }

  public func saveDraft(_ text: String) async {
    guard let room = opened?.room else { return }
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      try? await room.clearComposerDraft(threadRoot: threadRoot)
    } else {
      try? await room.saveComposerDraft(
        draft: ComposerDraft(
          plainText: text, htmlText: nil, draftType: .newMessage, attachments: []),
        threadRoot: threadRoot)
    }
  }

  public func retrySend(transactionId: String) async {
    guard let opened else { return }
    if !opened.room.isSendQueueEnabled() { opened.room.enableSendQueue(enable: true) }
    try? await opened.sendHandles.handle(of: transactionId)?.tryResend()
  }

  public func discardUnsent(transactionId: String) async throws(TimelineError) {
    let timeline = try openedTimeline()
    do {
      try await timeline.redactEvent(
        eventOrTransactionId: .transactionId(transactionId: transactionId), reason: nil)
    } catch {
      throw Self.failure("discardUnsent", error)
    }
  }

  public func report(eventId: String, reason: String?) async throws(TimelineError) {
    let room = try openedState().room
    do { try await room.reportContent(eventId: eventId, reason: reason) } catch {
      throw Self.failure("report", error)
    }
  }

  public func ignore(userId: String) async throws(TimelineError) {
    let client = try openedState().client
    do { try await client.client.ignoreUser(userId: userId) } catch {
      throw Self.failure("ignore", error)
    }
  }

  static func content(_ text: String, isEmote: Bool = false, emotes: [String: String] = [:])
    -> RoomMessageEventContentWithoutRelation
  {
    let content: RoomMessageEventContentWithoutRelation
    if let spoiler = RichMarkdown.content(text, emotes: emotes) {
      content =
        isEmote
        ? messageEventContentFromHtmlAsEmote(body: spoiler.body, htmlBody: spoiler.html)
        : messageEventContentFromHtml(body: spoiler.body, htmlBody: spoiler.html)
    } else {
      content =
        isEmote
        ? messageEventContentFromMarkdownAsEmote(md: text)
        : messageEventContentFromMarkdown(md: text)
    }
    let userIds = mentionedUserIds(in: text)
    let room = mentionsRoom(text)
    return userIds.isEmpty && !room
      ? content : content.withMentions(mentions: Mentions(userIds: userIds, room: room))
  }

  static func mentionsRoom(_ text: String) -> Bool {
    text.contains(/(^|\s)@room\b/)
  }

  static func mentionedUserIds(in text: String) -> [String] {
    var ids: [String] = []
    for match in text.matches(of: /https:\/\/matrix\.to\/#\/(@[^)\s\/?]+)/) {
      let id = String(match.output.1)
      if !ids.contains(id) { ids.append(id) }
    }
    return ids
  }
}
