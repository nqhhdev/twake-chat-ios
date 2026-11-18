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
  /// The root of the thread this timeline shows, or `nil` for the room's main timeline.
  private let threadRoot: String?
  /// Typing subscriptions, cancelled when the timeline closes.
  private var typingHandles: [TaskHandle] = []
  private let clientProxy: @Sendable () async -> ClientProxy?
  private var opened: Opened?

  /// - Parameters:
  ///   - roomId: The room this timeline shows.
  ///   - authentication: Gives the signed-in client.
  ///   - content: Shows only this kind of message, for a chat details tab.
  ///   - threadRoot: Shows this thread (its root and replies); what is sent goes into it.
  public init(
    roomId: String, authentication: MatrixAuthenticationRepository,
    only content: RoomContentKind? = nil, threadRoot: String? = nil
  ) {
    self.roomId = roomId
    self.content = content
    self.threadRoot = threadRoot
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
      let configuration =
        if let content { Self.configuration(only: content) } else {
          Self.configuration(threadRoot: threadRoot)
        }
      timeline = try await room.timelineWithConfiguration(configuration: configuration)
    } catch let error as TimelineError {
      throw error
    } catch {
      DebugLog.failure("openTimeline", error)
      throw .unavailable
    }
    let ownUserId = try? client.userId
    let (items, itemsContinuation) = AsyncStream<[Domain.TimelineItem]>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    let (diffs, diffsContinuation) = AsyncStream<[TimelineDiff]>.makeStream()
    // The listener is called on an SDK thread; diffs are applied in order by one task, which keeps the client alive
    // until it ends.
    let sendHandles = SendHandles()
    let applying = Task { [client] in
      var mapped: [Domain.TimelineItem?] = []
      for await batch in diffs {
        guard !Task.isCancelled else { continue }
        for diff in batch {
          await ListDiff(diff).map { item in
            sendHandles.note(item)
            return TimelineItemMapper.item(item, ownUserId: ownUserId)
          }.apply(to: &mapped)
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
      await objects.cancelEntries()
      diffsContinuation.finish()
      applying.cancel()
      throw .unavailable
    }
    // Loads the room's members so senders show their display names, not their Matrix ids; the timeline updates the
    // items it already published when the profiles arrive.
    Task { [timeline] in await timeline.fetchMembers() }
    opened = Opened(
      client: client, objects: objects, room: room, timeline: timeline, diffs: diffsContinuation,
      applying: applying, sendHandles: sendHandles)
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

  /// The room's main timeline, where a thread's replies are hidden and its root shows their count (`m.thread`), or one
  /// thread's timeline, in which messages are sent as replies in that thread. Both track read receipts. `reportUtds`
  /// stays off: the SDK refuses it without a UTD hook manager, which this client does not set.
  static func configuration(threadRoot: String?) -> TimelineConfiguration {
    TimelineConfiguration(
      focus: threadRoot.map { .thread(rootEventId: $0) } ?? .live(hideThreadedEvents: true),
      filter: .all, internalIdPrefix: threadRoot.map { "thread-\($0)" },
      dateDividerMode: .daily, trackReadReceipts: .allEvents, reportUtds: false)
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

  public func send(emote text: String) async throws(TimelineError) {
    let timeline = try openedTimeline()
    do {
      _ = try await timeline.send(msg: Self.content(text, isEmote: true))
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
    let url = attachment.fileURL
    let size = AttachmentMetadata.size(of: url, given: attachment.size)
    let mimeType = Self.mimeType(for: attachment)
    do {
      let handle: SendAttachmentJoinHandle
      switch attachment.kind {
      case .image(let width, let height):
        let image = AttachmentMetadata.image(at: url, width: width, height: height)
        handle = try timeline.sendImage(
          params: params, thumbnailSource: nil,
          imageInfo: ImageInfo(
            height: image.height, width: image.width, mimetype: mimeType, size: size,
            thumbnailInfo: nil, thumbnailSource: nil, blurhash: image.blurhash, isAnimated: nil))
      case .video(let width, let height, let duration):
        let video = await AttachmentMetadata.video(
          at: url, width: width, height: height, duration: duration)
        handle = try timeline.sendVideo(
          params: params, thumbnailSource: nil,
          videoInfo: VideoInfo(
            duration: video.duration ?? 0, height: video.height, width: video.width,
            mimetype: mimeType, size: size, thumbnailInfo: nil, thumbnailSource: nil,
            blurhash: video.blurhash))
      case .audio(let duration):
        let seconds = await AttachmentMetadata.audioDuration(of: url, given: duration)
        handle = try timeline.sendAudio(
          params: params,
          audioInfo: AudioInfo(duration: seconds, size: size, mimetype: mimeType))
      case .voice(let duration, let waveform):
        handle = try timeline.sendVoiceMessage(
          params: params,
          audioInfo: AudioInfo(duration: duration, size: size, mimetype: mimeType),
          waveform: waveform)
      case .file:
        handle = try timeline.sendFile(
          params: params,
          fileInfo: FileInfo(
            mimetype: mimeType, size: size, thumbnailInfo: nil, thumbnailSource: nil))
      }
      try await handle.join()
    } catch {
      DebugLog.failure("sendAttachment", error)
      throw .requestFailed
    }
  }

  /// The SDK refuses an attachment without a MIME type (`RoomError.InvalidAttachmentMimeType`), which a file whose
  /// extension the system does not know has none of; such a file goes as `application/octet-stream` (spec, `m.file`).
  static func mimeType(for attachment: OutgoingAttachment) -> String {
    if let type = attachment.mimeType, !type.isEmpty { return type }
    return switch attachment.kind {
    case .image: "image/jpeg"
    case .video: "video/mp4"
    case .audio, .voice: "audio/ogg"
    case .file: "application/octet-stream"
    }
  }

  public func createPoll(_ draft: PollDraft) async throws(TimelineError) {
    let timeline = try openedTimeline()
    let answers = draft.cleanAnswers
    do {
      try await timeline.createPoll(
        question: draft.question.trimmingCharacters(in: .whitespacesAndNewlines),
        answers: Array(answers.prefix(PollDraft.maxAnswers)),
        maxSelections: draft.allowsMultipleChoices ? UInt8(clamping: answers.count) : 1,
        pollKind: draft.hidesResults ? .undisclosed : .disclosed)
    } catch {
      DebugLog.failure("createPoll", error)
      throw .requestFailed
    }
  }

  public func vote(_ answerIds: [String], in pollEventId: String) async throws(TimelineError) {
    let timeline = try openedTimeline()
    do {
      try await timeline.sendPollResponse(pollStartEventId: pollEventId, answers: answerIds)
    } catch {
      DebugLog.failure("sendPollResponse", error)
      throw .requestFailed
    }
  }

  public func endPoll(_ pollEventId: String) async throws(TimelineError) {
    let timeline = try openedTimeline()
    do {
      // The fallback text of `m.poll.end`, for clients without polls.
      try await timeline.endPoll(pollStartEventId: pollEventId, text: "The poll has ended.")
    } catch {
      DebugLog.failure("endPoll", error)
      throw .requestFailed
    }
  }

  public func identityWarnings() async -> AsyncStream<[IdentityWarning]> {
    guard let opened else { return AsyncStream { $0.finish() } }
    let room = opened.room
    let (stream, continuation) = AsyncStream<[IdentityWarning]>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    let states = IdentityStates()
    let listener = IdentityListener { changes in
      Task {
        let current = await states.apply(changes)
        var warnings: [IdentityWarning] = []
        for (userId, kind) in current.sorted(by: { $0.key < $1.key }) {
          let name =
            ((try? await room.memberDisplayName(userId: userId)) ?? nil)
            .flatMap { $0.isEmpty ? nil : $0 } ?? userId
          warnings.append(IdentityWarning(userId: userId, name: name, kind: kind))
        }
        continuation.yield(warnings)
      }
    }
    guard let handle = try? await room.subscribeToIdentityStatusChanges(listener: listener) else {
      continuation.finish()
      return stream
    }
    continuation.onTermination = { _ in handle.cancel() }
    typingHandles.append(handle)
    return stream
  }

  public func accept(_ warning: IdentityWarning) async throws(TimelineError) {
    guard let client = await clientProxy()?.client else { throw .notSignedIn }
    do {
      guard
        let identity = try await client.encryption().userIdentity(
          userId: warning.userId, fallbackToServer: false)
      else { throw TimelineError.requestFailed }
      switch warning.kind {
      case .changed: try await identity.pin()
      case .verifiedChanged: try await identity.withdrawVerification()
      }
    } catch {
      DebugLog.failure("acceptIdentity", error)
      throw .requestFailed
    }
  }

  /// Reads the room's state over `GET /rooms/{id}/state` (the pinned SDK reads no custom state event) and keeps the
  /// command announcements of joined members, under the unstable and the stable name, as the web does.
  public func botCommands() async -> [BotCommand] {
    guard let opened,
      let request = ClientServerRequest.make(
        client: opened.client.client, path: "rooms/\(ClientServerRequest.encode(roomId))/state"),
      let (data, response) = try? await URLSession.shared.data(for: request),
      (response as? HTTPURLResponse)?.statusCode == 200,
      let events = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else { return [] }
    var commands: [BotCommand] = []
    for event in events {
      guard let type = event["type"] as? String,
        type == "org.matrix.msc4332.commands" || type == "m.bot.commands",
        let bot = event["state_key"] as? String, !bot.isEmpty,
        let content = event["content"] as? [String: Any],
        let member = try? await opened.room.member(userId: bot), member.membership == .join
      else { continue }
      commands += BotCommand.commands(botUserId: bot, content: content)
    }
    return commands
  }

  /// The first page of the room's threads from the SDK's thread list (`/threads`), newest activity first.
  public func threads() async -> [ThreadListEntry] {
    guard let room = opened?.room else { return [] }
    let service = room.threadListService()
    do {
      try await service.paginate()
    } catch {
      DebugLog.failure("threadList", error)
      return []
    }
    return service.items().map(TimelineItemMapper.threadEntry)
      .sorted { $0.latestDate > $1.latestDate }
  }

  public func editHistory(of eventId: String) async -> [MessageVersion]? {
    guard let opened, (try? await opened.room.latestEncryptionState()) == .notEncrypted else {
      return nil
    }
    let room = ClientServerRequest.encode(roomId)
    let event = ClientServerRequest.encode(eventId)
    let client = opened.client.client
    async let original = Self.data(
      ClientServerRequest.make(client: client, path: "rooms/\(room)/event/\(event)"))
    async let relations = Self.data(
      ClientServerRequest.make(
        client: client, path: "rooms/\(room)/relations/\(event)/m.replace?limit=50", version: "v1"))
    return MessageVersion.versions(original: await original, relations: await relations)
  }

  private static func data(_ request: URLRequest?) async -> Data? {
    guard let request, let (data, response) = try? await URLSession.shared.data(for: request),
      (response as? HTTPURLResponse)?.statusCode == 200
    else { return nil }
    return data
  }

  public func send(command: BotCommand, text: String) async throws(TimelineError) {
    let room = try openedState().room
    guard let data = try? JSONSerialization.data(withJSONObject: command.content(for: text)),
      let content = String(data: data, encoding: .utf8)
    else { throw .requestFailed }
    do {
      try await room.sendRaw(eventType: "m.room.message", content: content)
    } catch {
      DebugLog.failure("sendCommand", error)
      throw .requestFailed
    }
  }

  public func recentReactions() async -> [String] {
    guard let client = await clientProxy()?.client,
      let recents = try? await client.getRecentEmojis()
    else { return [] }
    return recents.map(\.emoji)
  }

  public func addRecentReaction(_ key: String) async {
    try? await clientProxy()?.client.addRecentEmoji(emoji: key)
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
      MediaBatch.remove(from: &content)
      let body = try JSONSerialization.data(withJSONObject: content)
      try await target.sendRaw(eventType: type, content: String(decoding: body, as: UTF8.self))
    } catch {
      throw .requestFailed
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
      throw .requestFailed
    }
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
  static func content(_ text: String, isEmote: Bool = false)
    -> RoomMessageEventContentWithoutRelation
  {
    let content =
      isEmote
      ? messageEventContentFromMarkdownAsEmote(md: text) : messageEventContentFromMarkdown(md: text)
    let userIds = mentionedUserIds(in: text)
    let room = mentionsRoom(text)
    return userIds.isEmpty && !room
      ? content : content.withMentions(mentions: Mentions(userIds: userIds, room: room))
  }

  /// The text names everyone: « @room » as a word of its own. The composer offers it only to those whose power level
  /// allows it; typed by someone else, servers ignore the mention (the push rule checks the sender's power level).
  static func mentionsRoom(_ text: String) -> Bool {
    text.contains(/(^|\s)@room\b/)
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
  public func retryDecryption(sessionIds: [String]) async {
    guard let timeline = try? openedTimeline() else { return }
    timeline.retryDecryption(sessionIds: sessionIds)
  }

  public func close() async {

    for handle in typingHandles { handle.cancel() }
    typingHandles = []
    guard let opened else { return }
    self.opened = nil
    opened.diffs.finish()
    opened.applying.cancel()
    await opened.client.release(opened.objects.id)
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
    let sendHandles: SendHandles
  }
}

/// The SDK send handles of the messages that failed to send, by transaction id, so one of them can be sent again
/// (`SendHandle.tryResend`). The timeline's applying task fills it; the proxy reads it.
private final class SendHandles: @unchecked Sendable {
  private let lock = NSLock()
  private var handles: [String: SendHandle] = [:]

  func note(_ item: MatrixRustSDK.TimelineItem) {
    guard let event = item.asEvent(), event.isOwn,
      case .transactionId(let id) = event.eventOrTransactionId,
      case .sendingFailed = event.localSendState,
      let handle = event.lazyProvider.getSendHandle()
    else { return }
    lock.withLock { handles[id] = handle }
  }

  func handle(of transactionId: String) -> SendHandle? {
    lock.withLock { handles[transactionId] }
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
/// The members in violation, kept as the SDK reports changes (it sends only what changed).
private actor IdentityStates {
  private var violations: [String: IdentityWarning.Kind] = [:]

  func apply(_ changes: [IdentityStatusChange]) -> [String: IdentityWarning.Kind] {
    for change in changes {
      switch change.changedTo {
      case .pinViolation: violations[change.userId] = .changed
      case .verificationViolation: violations[change.userId] = .verifiedChanged
      default: violations[change.userId] = nil
      }
    }
    return violations
  }
}

private final class IdentityListener: IdentityStatusChangeListener {
  private let onChange: @Sendable ([IdentityStatusChange]) -> Void

  init(_ onChange: @escaping @Sendable ([IdentityStatusChange]) -> Void) {
    self.onChange = onChange
  }

  func call(identityStatusChange: [IdentityStatusChange]) {
    onChange(identityStatusChange)
  }
}

/// Calls back with the ids of the people typing in a room; the room screen and the room list use it.
final class TypingListener: TypingNotificationsListener {
  private let onChange: @Sendable ([String]) -> Void

  init(_ onChange: @escaping @Sendable ([String]) -> Void) {
    self.onChange = onChange
  }

  func call(typingUserIds: [String]) {
    onChange(typingUserIds)
  }
}
