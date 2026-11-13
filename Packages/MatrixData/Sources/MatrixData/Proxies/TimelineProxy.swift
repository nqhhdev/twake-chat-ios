import Domain
import Foundation
import MatrixRustSDK

/// `TimelineRepository` on the SDK timeline of one room (ADR 0006). It opens the room's timeline on the signed-in
/// client, applies each `TimelineDiff` to its list and publishes the list as Domain items, oldest first. The SDK room,
/// timeline and listener handle are kept by the client while sync runs, so they are released before it
/// (`ClientProxy.keepWhileSyncing`), and released when the screen closes. Nothing here logs: items hold message content (ADR 0009).
public actor TimelineProxy: TimelineRepository {
  /// How many events one "load older" asks for, as the Flutter app's timeline does.
  static let pageSize: UInt16 = 30

  private let roomId: String
  /// The one kind of message this timeline shows, for a chat details tab; `nil` shows the whole room.
  private let content: RoomContentKind?
  /// Typing subscriptions, cancelled when the timeline closes.
  private var typingHandles: [TaskHandle] = []
  private let clientProxy: @Sendable () async -> ClientProxy?
  private var opened: Opened?

  /// - Parameters:
  ///   - roomId: The room this timeline shows.
  ///   - authentication: Gives the signed-in client.
  ///   - content: Shows only this kind of message, for a chat details tab.
  public init(
    roomId: String, authentication: MatrixAuthenticationRepository,
    only content: RoomContentKind? = nil
  ) {
    self.roomId = roomId
    self.content = content
    clientProxy = { await authentication.clientProxy }
  }

  public func open() async throws(TimelineError) -> AsyncStream<[Domain.TimelineItem]> {
    await close()
    guard let client = await clientProxy() else { throw .notSignedIn }
    let timeline: Timeline
    let room: Room
    do {
      _ = try await client.startSync()
      guard let found = try client.client.getRoom(roomId: roomId) else {
        throw TimelineError.roomNotFound
      }
      room = found
      if let content {
        timeline = try await room.timelineWithConfiguration(
          configuration: Self.configuration(only: content))
      } else {
        timeline = try await room.timeline()
      }
    } catch let error as TimelineError {
      throw error
    } catch {
      throw .unavailable
    }
    let ownUserId = try? client.userId
    let (items, itemsContinuation) = AsyncStream<[Domain.TimelineItem]>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    let (diffs, diffsContinuation) = AsyncStream<[TimelineDiff]>.makeStream()
    // The listener is called on an SDK thread; diffs are applied in order by one task, which keeps the client alive
    // until it ends.
    let applying = Task { [client] in
      var mapped: [Domain.TimelineItem?] = []
      for await batch in diffs {
        guard !Task.isCancelled else { continue }
        for diff in batch {
          await ListDiff(diff).map { TimelineItemMapper.item($0, ownUserId: ownUserId) }.apply(
            to: &mapped)
        }
        itemsContinuation.yield(mapped.compactMap { $0 })
      }
      itemsContinuation.finish()
      withExtendedLifetime(client) {}
    }
    let handle = await timeline.addListener(listener: DiffListener(diffsContinuation))
    let objects = SyncBoundObjects(entries: handle, objects: [room, timeline])
    let kept = await client.keepWhileSyncing(objects)
    guard kept else {
      handle.cancel()
      diffsContinuation.finish()
      applying.cancel()
      throw .unavailable
    }
    // Loads the room's members so senders show their display names, not their Matrix ids; the timeline updates the
    // items it already published when the profiles arrive.
    Task { [timeline] in await timeline.fetchMembers() }
    opened = Opened(
      client: client, objects: objects, room: room, timeline: timeline, diffs: diffsContinuation,
      applying: applying)
    itemsContinuation.onTermination = { _ in diffsContinuation.finish() }
    return items
  }

  /// A timeline of one kind of message, as the Flutter chat details tabs list them (`isVideoOrImage`, `isAFile`, and
  /// text that may hold a link, which the feature checks); it does not track read receipts.
  static func configuration(only content: RoomContentKind) -> TimelineConfiguration {
    let types: [RoomMessageEventMessageType] =
      switch content {
      case .media: [.image, .video]
      case .files: [.file]
      case .links, .text: [.text, .notice, .emote]
      }
    return TimelineConfiguration(
      focus: .live(hideThreadedEvents: false), filter: .onlyMessage(types: types),
      internalIdPrefix: content.rawValue, dateDividerMode: .monthly, trackReadReceipts: .disabled,
      reportUtds: false)
  }

  public func loadOlder() async throws(TimelineError) -> Bool {
    let timeline = try openedTimeline()
    do {
      return try await timeline.paginateBackwards(numEvents: Self.pageSize)
    } catch {
      throw .requestFailed
    }
  }

  public func send(text: String) async throws(TimelineError) {
    let timeline = try openedTimeline()
    do {
      _ = try await timeline.send(msg: Self.content(text))
    } catch {
      throw .requestFailed
    }
  }

  public func sendAttachment(_ attachment: OutgoingAttachment) async throws(TimelineError) {
    let timeline = try openedTimeline()
    let params = UploadParameters(
      source: .file(filename: attachment.fileURL.path(percentEncoded: false)),
      caption: attachment.caption,
      formattedCaption: nil, mentions: nil, inReplyTo: attachment.replyTo)
    let size = attachment.size.map { UInt64(max(0, $0)) }
    do {
      let handle: SendAttachmentJoinHandle
      switch attachment.kind {
      case .image(let width, let height):
        handle = try timeline.sendImage(
          params: params, thumbnailSource: nil,
          imageInfo: ImageInfo(
            height: height.map(UInt64.init), width: width.map(UInt64.init),
            mimetype: attachment.mimeType,
            size: size, thumbnailInfo: nil, thumbnailSource: nil, blurhash: nil, isAnimated: nil))
      case .video(let width, let height, let duration):
        handle = try timeline.sendVideo(
          params: params, thumbnailSource: nil,
          videoInfo: VideoInfo(
            duration: duration, height: height.map(UInt64.init), width: width.map(UInt64.init),
            mimetype: attachment.mimeType, size: size, thumbnailInfo: nil, thumbnailSource: nil,
            blurhash: nil))
      case .audio(let duration):
        handle = try timeline.sendAudio(
          params: params,
          audioInfo: AudioInfo(duration: duration, size: size, mimetype: attachment.mimeType))
      case .voice(let duration, let waveform):
        handle = try timeline.sendVoiceMessage(
          params: params,
          audioInfo: AudioInfo(duration: duration, size: size, mimetype: attachment.mimeType),
          waveform: waveform)
      case .file:
        handle = try timeline.sendFile(
          params: params,
          fileInfo: FileInfo(
            mimetype: attachment.mimeType, size: size, thumbnailInfo: nil, thumbnailSource: nil))
      }
      try await handle.join()
    } catch {
      throw .requestFailed
    }
  }

  public func setTyping(_ isTyping: Bool) async {
    try? await opened?.room.typingNotice(isTyping: isTyping)
  }

  public func typingMembers() async -> AsyncStream<[String]> {
    guard let opened else { return AsyncStream { $0.finish() } }
    let room = opened.room
    let ownUserId = try? opened.client.userId
    let (names, continuation) = AsyncStream<[String]>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    let listener = TypingListener { userIds in
      Task {
        var result: [String] = []
        for userId in userIds where userId != ownUserId {
          let name = (try? await room.memberDisplayName(userId: userId)) ?? nil
          result.append(name.flatMap { $0.isEmpty ? nil : $0 } ?? userId)
        }
        continuation.yield(result)
      }
    }
    let handle = room.subscribeToTypingNotifications(listener: listener)
    continuation.onTermination = { _ in handle.cancel() }
    typingHandles.append(handle)
    return names
  }

  public func reply(text: String, to eventId: String) async throws(TimelineError) {
    let timeline = try openedTimeline()
    do {
      try await timeline.sendReply(msg: Self.content(text), eventId: eventId)
    } catch {
      throw .requestFailed
    }
  }

  public func edit(eventId: String, text: String) async throws(TimelineError) {
    let timeline = try openedTimeline()
    do {
      try await timeline.edit(
        eventOrTransactionId: .eventId(eventId: eventId),
        newContent: .roomMessage(content: Self.content(text)))
    } catch {
      throw .requestFailed
    }
  }

  public func redact(eventId: String) async throws(TimelineError) {
    let timeline = try openedTimeline()
    do {
      try await timeline.redactEvent(eventOrTransactionId: .eventId(eventId: eventId), reason: nil)
    } catch {
      throw .requestFailed
    }
  }

  public func toggleReaction(_ key: String, on eventId: String) async throws(TimelineError) {
    let timeline = try openedTimeline()
    do {
      _ = try await timeline.toggleReaction(itemId: .eventId(eventId: eventId), key: key)
    } catch {
      throw .requestFailed
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
      throw .requestFailed
    }
  }

  public func pinnedMessages() async -> [TimelineMessage] {
    guard let opened, let info = try? await opened.room.roomInfo() else { return [] }
    let ownUserId = try? opened.client.userId
    var messages: [TimelineMessage] = []
    for eventId in info.pinnedEventIds {
      guard let event = try? await opened.timeline.getEventTimelineItemByEventId(eventId: eventId),
        let message = TimelineItemMapper.message(from: event, ownUserId: ownUserId)
      else { continue }
      messages.append(message)
    }
    return messages
  }

  /// Sends the original event's content to the other room, without the reply or edit it relates to, so pictures and
  /// files are forwarded with their media (encrypted media keep their keys in the content, as other clients forward).
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
      let body = try JSONSerialization.data(withJSONObject: content)
      try await target.sendRaw(eventType: type, content: String(decoding: body, as: UTF8.self))
    } catch {
      throw .requestFailed
    }
  }

  public func loadDraft() async -> String? {
    guard let draft = try? await opened?.room.loadComposerDraft(threadRoot: nil) else { return nil }
    return draft.plainText.isEmpty ? nil : draft.plainText
  }

  public func saveDraft(_ text: String) async {
    guard let room = opened?.room else { return }
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      try? await room.clearComposerDraft(threadRoot: nil)
    } else {
      try? await room.saveComposerDraft(
        draft: ComposerDraft(
          plainText: text, htmlText: nil, draftType: .newMessage, attachments: []),
        threadRoot: nil)
    }
  }

  public func retryFailedSends() async {
    opened?.room.enableSendQueue(enable: true)
  }

  public func report(eventId: String, reason: String?) async throws(TimelineError) {
    let room = try openedState().room
    do { try await room.reportContent(eventId: eventId, reason: reason) } catch {
      throw .requestFailed
    }
  }

  public func ignore(userId: String) async throws(TimelineError) {
    let client = try openedState().client
    do { try await client.client.ignoreUser(userId: userId) } catch { throw .requestFailed }
  }

  /// The message content of a Markdown text. A link to a user (`[Name](https://matrix.to/#/@user:server)`, as the
  /// composer writes a mention) also lists that user in the intentional mentions, so they are notified.
  static func content(_ text: String) -> RoomMessageEventContentWithoutRelation {
    let content = messageEventContentFromMarkdown(md: text)
    let userIds = mentionedUserIds(in: text)
    return userIds.isEmpty
      ? content : content.withMentions(mentions: Mentions(userIds: userIds, room: false))
  }

  /// The Matrix ids of the users linked with matrix.to in `text`, once each, in order.
  static func mentionedUserIds(in text: String) -> [String] {
    var ids: [String] = []
    for match in text.matches(of: /https:\/\/matrix\.to\/#\/(@[^)\s\/?]+)/) {
      let id = String(match.output.1)
      if !ids.contains(id) { ids.append(id) }
    }
    return ids
  }

  public func markAsRead() async {
    try? await opened?.timeline.markAsRead(receiptType: .read)
  }

  /// Stops following the timeline and releases the SDK room and timeline while the client is alive.
  public func close() async {
    for handle in typingHandles { handle.cancel() }
    typingHandles = []
    guard let opened else { return }
    self.opened = nil
    opened.diffs.finish()
    opened.applying.cancel()
    await opened.client.release(opened.objects)
  }

  private func openedState() throws(TimelineError) -> Opened {
    guard let opened else { throw .unavailable }
    return opened
  }

  private func openedTimeline() throws(TimelineError) -> Timeline {
    guard let opened else { throw .unavailable }
    return opened.timeline
  }

  private struct Opened {
    let client: ClientProxy
    let objects: SyncBoundObjects
    let room: Room
    let timeline: Timeline
    let diffs: AsyncStream<[TimelineDiff]>.Continuation
    let applying: Task<Void, Never>
  }
}

/// Queues the SDK's timeline diffs for `TimelineProxy`, in the order they arrive.
private final class DiffListener: TimelineListener {
  private let diffs: AsyncStream<[TimelineDiff]>.Continuation

  init(_ diffs: AsyncStream<[TimelineDiff]>.Continuation) {
    self.diffs = diffs
  }

  func onUpdate(diff: [TimelineDiff]) {
    diffs.yield(diff)
  }
}

/// Forwards the SDK's typing notifications to `TimelineProxy`.
private final class TypingListener: TypingNotificationsListener {
  private let onChange: @Sendable ([String]) -> Void

  init(_ onChange: @escaping @Sendable ([String]) -> Void) {
    self.onChange = onChange
  }

  func call(typingUserIds: [String]) {
    onChange(typingUserIds)
  }
}
