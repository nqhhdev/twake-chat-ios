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

  let roomId: String
  let content: RoomContentKind?
  let threadRoot: String?
  var typingHandles: [TaskHandle] = []
  let clientProxy: @Sendable () async -> ClientProxy?
  let index: MessageIndex?
  var opened: Opened?
  var knownEmotes: [String: String] = [:]
  var delayedEventsSupported: Bool?
  let capabilities: (any ServerCapabilitiesRepository)?

  /// - Parameters:
  ///   - roomId: The room this timeline shows.
  ///   - authentication: Gives the signed-in client.
  ///   - content: Shows only this kind of message, for a chat details tab.
  ///   - threadRoot: Shows this thread (its root and replies); what is sent goes into it.
  public init(
    roomId: String, authentication: MatrixAuthenticationRepository,
    only content: RoomContentKind? = nil, threadRoot: String? = nil, index: MessageIndex? = nil,
    capabilities: (any ServerCapabilitiesRepository)? = nil
  ) {
    self.capabilities = capabilities
    self.roomId = roomId
    self.content = content
    self.threadRoot = threadRoot
    self.index = index
    clientProxy = { await authentication.clientProxy }
  }

  public func open() async throws(TimelineError) -> AsyncStream<[Domain.TimelineItem]> {
    await close()
    guard let client = await clientProxy() else { throw .notSignedIn }
    let timeline: Timeline
    let room: Room
    do {
      // Bound the wait: startSync or the room lookup can stall (store lock, first sync). Issue #84.
      let roomId = roomId
      let content = content
      let threadRoot = threadRoot
      (room, timeline) = try await withTimeout(.seconds(15)) {
        _ = try await client.startSync()
        guard let found = try await client.room(id: roomId) else {
          throw TimelineError.roomNotFound
        }
        let configuration =
          if let content { Self.configuration(only: content) } else {
            Self.configuration(threadRoot: threadRoot)
          }
        let timeline = try await Self.timeline(in: found, configuration: configuration)
        return (found, timeline)
      }
    } catch is WaitTimeout {
      DebugLog.failure("openTimeline", WaitTimeout())
      throw .unavailable
    } catch let error as TimelineError {
      throw error
    } catch {
      DebugLog.failure("openTimeline", error)
      throw .unavailable
    }
    let ownUserId = try? client.userId
    let (items, itemsContinuation) = AsyncStream<[Domain.TimelineItem]>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    // The SDK may send no first diff for a room with nothing cached, which left the screen loading forever. An empty
    // list first lets it show the timeline and load older pages; the SDK's first items replace it in the buffer.
    itemsContinuation.yield([])
    let (diffs, diffsContinuation) = AsyncStream<[TimelineDiff]>.makeStream()
    // The listener is called on an SDK thread; diffs are applied in order by one task, which keeps the client alive
    // until it ends.
    let sendHandles = SendHandles()
    let recorder = await room.isEncrypted() ? index.map { IndexRecorder(index: $0) } : nil
    let applying = Task { [client, roomId] in
      var mapped: [Domain.TimelineItem?] = []
      for await batch in diffs {
        guard !Task.isCancelled else { continue }
        for diff in batch {
          await ListDiff(diff).map { item in
            sendHandles.note(item)
            return TimelineItemMapper.item(item, ownUserId: ownUserId)
          }.apply(to: &mapped)
        }
        let items = mapped.compactMap { $0 }
        itemsContinuation.yield(items)
        await recorder?.record(roomId: roomId, items: items)
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

  static func timeline(in room: Room, configuration: TimelineConfiguration) async throws -> Timeline
  {
    try await StoreLock.retrying {
      try await room.timelineWithConfiguration(configuration: configuration)
    }
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
      throw Self.failure("loadOlder", error)
    }
  }

  public func send(text: String) async throws(TimelineError) {
    let timeline = try openedTimeline()
    do {
      _ = try await timeline.send(msg: Self.content(text, emotes: knownEmotes))
    } catch {
      throw Self.failure("send", error)
    }
  }

  public func send(emote text: String) async throws(TimelineError) {
    let timeline = try openedTimeline()
    do {
      _ = try await timeline.send(msg: Self.content(text, isEmote: true, emotes: knownEmotes))
    } catch {
      throw Self.failure("sendEmote", error)
    }
  }

  public func sendAttachment(_ attachment: OutgoingAttachment) async throws(TimelineError) {
    if let batchId = attachment.batchId {
      switch attachment.kind {
      case .image, .video:
        try await sendAlbumItem(attachment, batchId: batchId)
        return
      default: break
      }
    }
    let timeline = try openedTimeline()
    let params = UploadParameters(
      source: .file(filename: attachment.fileURL.path(percentEncoded: false)),
      caption: attachment.caption,
      formattedCaption: nil, mentions: nil, inReplyTo: attachment.replyTo)
    let url = attachment.fileURL
    let size = AttachmentMetadata.size(of: url, given: attachment.size)
    let mimeType = Self.mimeType(for: attachment)
    // The SDK reads the thumbnail file when the attachment is queued, so it can go once `join` returns.
    var thumbnail: AttachmentMetadata.Thumbnail?
    defer { if let thumbnail { try? FileManager.default.removeItem(at: thumbnail.url) } }
    do {
      let handle: SendAttachmentJoinHandle
      switch attachment.kind {
      case .image(let width, let height):
        let image = AttachmentMetadata.image(at: url, width: width, height: height)
        thumbnail = AttachmentMetadata.imageThumbnail(at: url)
        handle = try timeline.sendImage(
          params: params, thumbnailSource: Self.source(of: thumbnail),
          imageInfo: ImageInfo(
            height: image.height, width: image.width, mimetype: mimeType, size: size,
            thumbnailInfo: Self.info(of: thumbnail), thumbnailSource: nil,
            blurhash: image.blurhash, isAnimated: nil))
      case .video(let width, let height, let duration):
        let video = await AttachmentMetadata.video(
          at: url, width: width, height: height, duration: duration)
        thumbnail = await AttachmentMetadata.videoThumbnail(at: url)
        handle = try timeline.sendVideo(
          params: params, thumbnailSource: Self.source(of: thumbnail),
          videoInfo: VideoInfo(
            duration: video.duration ?? 0, height: video.height, width: video.width,
            mimetype: mimeType, size: size, thumbnailInfo: Self.info(of: thumbnail),
            thumbnailSource: nil, blurhash: video.blurhash))
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
      throw Self.failure("sendAttachment", error)
    }
  }

  private static func source(of thumbnail: AttachmentMetadata.Thumbnail?) -> UploadSource? {
    thumbnail.map { .file(filename: $0.url.path(percentEncoded: false)) }
  }

  private static func info(of thumbnail: AttachmentMetadata.Thumbnail?) -> ThumbnailInfo? {
    thumbnail.map {
      ThumbnailInfo(height: $0.height, width: $0.width, mimetype: "image/jpeg", size: $0.size)
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
      throw Self.failure("createPoll", error)
    }
  }

  public func vote(_ answerIds: [String], in pollEventId: String) async throws(TimelineError) {
    let timeline = try openedTimeline()
    do {
      try await timeline.sendPollResponse(pollStartEventId: pollEventId, answers: answerIds)
    } catch {
      throw Self.failure("sendPollResponse", error)
    }
  }

  public func endPoll(_ pollEventId: String) async throws(TimelineError) {
    let timeline = try openedTimeline()
    do {
      // The fallback text of `m.poll.end`, for clients without polls.
      try await timeline.endPoll(pollStartEventId: pollEventId, text: "The poll has ended.")
    } catch {
      throw Self.failure("endPoll", error)
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
      throw Self.failure("acceptIdentity", error)
    }
  }

  /// Reads the room's state over `GET /rooms/{id}/state` (the pinned SDK reads no custom state event) and keeps the
  public func send(command: BotCommand, text: String) async throws(TimelineError) {
    let room = try openedState().room
    guard let data = try? JSONSerialization.data(withJSONObject: command.content(for: text)),
      let content = String(data: data, encoding: .utf8)
    else { throw .requestFailed }
    do {
      try await room.sendRaw(eventType: "m.room.message", content: content)
    } catch {
      throw Self.failure("sendCommand", error)
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

  func openedState() throws(TimelineError) -> Opened {
    guard let opened else { throw .unavailable }
    return opened
  }

  func openedTimeline() throws(TimelineError) -> Timeline {
    guard let opened else { throw .unavailable }
    return opened.timeline
  }

  static func failure(_ operation: String, _ error: any Error) -> TimelineError {
    DebugLog.failure(operation, error)
    return TimelineErrorMapper.map(error)
  }

  struct Opened {
    let client: ClientProxy
    let objects: SyncBoundObjects
    let room: Room
    let timeline: Timeline
    let diffs: AsyncStream<[TimelineDiff]>.Continuation
    let applying: Task<Void, Never>
    let sendHandles: SendHandles
  }
}
