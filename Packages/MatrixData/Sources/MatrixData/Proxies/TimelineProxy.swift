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
  private let index: MessageIndex?
  private var opened: Opened?
  private var knownEmotes: [String: String] = [:]
  private var delayedEventsSupported: Bool?
  private let capabilities: (any ServerCapabilitiesRepository)?

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

  private func sendAlbumItem(_ attachment: OutgoingAttachment, batchId: String)
    async throws(TimelineError)
  {
    let opened = try openedState()
    let client = opened.client.client
    let url = attachment.fileURL
    guard let data = try? Data(contentsOf: url) else { throw .uploadFailed }
    let isEncrypted = (try? await opened.room.latestEncryptionState()) != .notEncrypted
    let mimeType = Self.mimeType(for: attachment)
    var isVideo = false
    var visual: AttachmentMetadata.Visual
    var thumbnail: AttachmentMetadata.Thumbnail?
    switch attachment.kind {
    case .video(let width, let height, let duration):
      isVideo = true
      visual = await AttachmentMetadata.video(
        at: url, width: width, height: height, duration: duration)
      thumbnail = await AttachmentMetadata.videoThumbnail(at: url)
    case .image(let width, let height):
      visual = AttachmentMetadata.image(at: url, width: width, height: height)
      thumbnail = AttachmentMetadata.imageThumbnail(at: url)
    default:
      throw .unsupportedType
    }
    defer { if let thumbnail { try? FileManager.default.removeItem(at: thumbnail.url) } }
    do {
      let media = try await Self.upload(
        data, mimeType: mimeType, encrypted: isEncrypted, client: client)
      var thumbnailMedia: AlbumItemContent.Media?
      var thumbnailInfo: [String: Any]?
      if let thumbnail, let thumbnailData = try? Data(contentsOf: thumbnail.url) {
        thumbnailMedia = try await Self.upload(
          thumbnailData, mimeType: "image/jpeg", encrypted: isEncrypted, client: client)
        thumbnailInfo = [
          "mimetype": "image/jpeg", "size": thumbnail.size, "w": thumbnail.width,
          "h": thumbnail.height,
        ]
      }
      let item = AlbumItemContent.Item(
        isVideo: isVideo, filename: url.lastPathComponent, caption: attachment.caption,
        mimeType: mimeType, size: AttachmentMetadata.size(of: url, given: attachment.size),
        width: visual.width, height: visual.height, blurhash: visual.blurhash,
        duration: isVideo ? visual.duration : nil, media: media, thumbnail: thumbnailMedia,
        thumbnailInfo: thumbnailInfo)
      let content = AlbumItemContent.content(
        item, batchId: batchId, replyTo: attachment.replyTo, threadRoot: threadRoot)
      let json = try JSONSerialization.data(withJSONObject: content)
      try await opened.room.sendRaw(
        eventType: "m.room.message", content: String(decoding: json, as: UTF8.self))
    } catch {
      throw Self.failure("sendAlbumItem", error)
    }
  }

  private static func upload(
    _ data: Data, mimeType: String, encrypted: Bool, client: Client
  ) async throws -> AlbumItemContent.Media {
    guard encrypted else {
      return .url(
        try await client.uploadMedia(mimeType: mimeType, data: data, progressWatcher: nil))
    }
    let sealed = try AttachmentCrypto.encrypt(data)
    let url = try await client.uploadMedia(
      mimeType: "application/octet-stream", data: sealed.data, progressWatcher: nil)
    return .file(sealed.file(url: url))
  }

  /// The SDK sends a thumbnail only when both its file and its info are given.
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

  public func gifsEnabled() async -> Bool {
    guard let opened else { return true }
    if await opened.room.isDirect() { return true }
    let room = ClientServerRequest.encode(roomId)
    guard
      let request = ClientServerRequest.make(
        client: opened.client.client, path: "rooms/\(room)/state/\(Self.gifsStateType)/"),
      let content = await ClientServerRequest.object(request)
    else { return true }
    return Self.gifsEnabled(content)
  }

  public func stickerPacks() async -> [StickerPack] {
    var seen = Set<String>()
    return await imagePacks().compactMap { pack in
      ImagePackMapper.pack(
        id: pack.id, content: pack.content, fallbackName: pack.fallbackName,
        source: Self.mediaSourceJSON)
    }
    .filter { seen.insert($0.id).inserted }
  }

  public func emotes() async -> [Emote] {
    var seen = Set<String>()
    let emotes = await imagePacks().flatMap { pack in
      ImagePackMapper.emotes(content: pack.content, source: Self.mediaSourceJSON)
    }
    .filter { seen.insert($0.shortcode).inserted }
    knownEmotes = Dictionary(emotes.map { ($0.shortcode, $0.url) }, uniquingKeysWith: { a, _ in a })
    return emotes
  }

  static func mediaSourceJSON(_ url: String) -> String? {
    try? MediaSource.fromUrl(url: url).toJson()
  }

  private struct PackContent: @unchecked Sendable {
    let id: String
    let content: [String: Any]
    let fallbackName: String
  }

  private func imagePacks() async -> [PackContent] {
    guard let opened else { return [] }
    let client = opened.client.client
    var packs: [PackContent] = []
    if let user = ImagePackMapper.eventContent(
      try? await client.accountData(eventType: ImagePackMapper.userPackType))
    {
      packs.append(PackContent(id: "user", content: user, fallbackName: "My stickers"))
    }
    let room = ClientServerRequest.encode(roomId)
    if let request = ClientServerRequest.make(client: client, path: "rooms/\(room)/state"),
      let data = await Self.data(request),
      let events = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    {
      for event in events where event["type"] as? String == ImagePackMapper.roomPackType {
        guard let key = event["state_key"] as? String,
          let content = event["content"] as? [String: Any]
        else { continue }
        packs.append(
          PackContent(
            id: "room:\(roomId):\(key)", content: content,
            fallbackName: key.isEmpty ? "Chat stickers" : key))
      }
    }
    let packRooms = ImagePackMapper.eventContent(
      try? await client.accountData(eventType: ImagePackMapper.packRoomsType))
    for packRoom in packRooms.map(ImagePackMapper.packRooms) ?? [] where packRoom.roomId != roomId {
      let other = packRoom.roomId
      let key = packRoom.stateKey
      let path =
        "rooms/\(ClientServerRequest.encode(other))/state/\(ImagePackMapper.roomPackType)/"
        + ClientServerRequest.encode(key)
      guard let request = ClientServerRequest.make(client: client, path: path),
        let content = await ClientServerRequest.object(request)
      else { continue }
      packs.append(
        PackContent(
          id: "room:\(other):\(key)", content: content,
          fallbackName: key.isEmpty ? "Stickers" : key))
    }
    return packs
  }

  public func send(sticker: Sticker) async throws(TimelineError) {
    let room = try openedState().room
    let content = ImagePackMapper.stickerContent(sticker, threadRoot: threadRoot)
    guard let data = try? JSONSerialization.data(withJSONObject: content),
      let json = String(data: data, encoding: .utf8)
    else { throw .requestFailed }
    do {
      try await room.sendRaw(eventType: "m.sticker", content: json)
    } catch {
      throw Self.failure("sendSticker", error)
    }
  }

  public func canSchedule() async -> Bool {
    guard let opened, threadRoot == nil,
      (try? await opened.room.latestEncryptionState()) == .notEncrypted
    else { return false }
    if let delayedEventsSupported { return delayedEventsSupported }
    if let capabilities {
      let supported = await capabilities.current().supports(DelayedEvents.feature)
      delayedEventsSupported = supported
      return supported
    }
    guard
      let request = ClientServerRequest.make(
        client: opened.client.client, path: "", version: "versions"),
      let versions = await ClientServerRequest.object(request)
    else { return false }
    let supported = DelayedEvents.supports(versions)
    delayedEventsSupported = supported
    return supported
  }

  public func schedule(text: String, at date: Date, replyTo: String?) async throws(ScheduleError) {
    guard let opened else { throw .failed }
    guard (try? await opened.room.latestEncryptionState()) == .notEncrypted else {
      throw .encryptedRoom
    }
    guard await canSchedule() else { throw .unsupported }
    let room = ClientServerRequest.encode(roomId)
    let path =
      "rooms/\(room)/send/m.room.message/\(UUID().uuidString)?\(DelayedEvents.delayParameter)="
      + String(DelayedEvents.delay(until: date))
    guard
      let request = ClientServerRequest.make(
        client: opened.client.client, path: path, method: "PUT",
        json: DelayedEvents.content(text: text, replyTo: replyTo, emotes: knownEmotes)),
      let (status, body) = await ClientServerRequest.answer(request)
    else { throw .failed }
    guard status == 200 else { throw DelayedEvents.error(status: status, body: body) }
  }

  public func scheduledMessages() async -> [ScheduledMessage] {
    guard let opened,
      let request = ClientServerRequest.make(
        client: opened.client.client, path: "delayed_events?status=scheduled",
        version: DelayedEvents.version),
      let object = await ClientServerRequest.object(request)
    else { return [] }
    return DelayedEvents.scheduled(object, roomId: roomId)
  }

  public func cancelScheduled(id: String) async -> Bool {
    await updateDelayedEvent(id: id, action: "cancel")
  }

  public func sendScheduledNow(id: String) async -> Bool {
    await updateDelayedEvent(id: id, action: "send")
  }

  private func updateDelayedEvent(id: String, action: String) async -> Bool {
    guard let client = opened?.client.client else { return false }
    let delay = ClientServerRequest.encode(id)
    if let request = ClientServerRequest.make(
      client: client, path: "delayed_events/\(delay)/\(action)", method: "POST", json: [:],
      version: DelayedEvents.version),
      let (status, _) = await ClientServerRequest.answer(request)
    {
      if status == 200 { return true }
      guard status == 404 || status == 400 || status == 405 else { return false }
    }
    guard
      let request = ClientServerRequest.make(
        client: client, path: "delayed_events/\(delay)", method: "POST",
        json: ["action": action], version: DelayedEvents.version)
    else { return false }
    return await ClientServerRequest.succeeds(request)
  }

  static let gifsStateType = ChannelSettings.gifsStateType

  static func gifsEnabled(_ content: [String: Any]) -> Bool {
    (content["enabled"] as? Bool) != false
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
    guard let opened else { return nil }
    guard (try? await opened.room.latestEncryptionState()) == .notEncrypted else {
      return await EncryptedEditHistory.versions(
        of: eventId, roomId: roomId, room: opened.room, client: opened.client.client)
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
        // Pinned long ago, so not among the loaded messages: read from the store or the homeserver, or the banner
        // would miss it until the user scrolls that far back (twake-on-matrix #2826, #211).
        messages.append(message)
      }
    }
    return messages
  }

  /// A pinned message that is not in the loaded timeline, with what the banner and the pinned list show: who wrote
  /// it, when, and its text or a short description. `nil` for what is not a message (or cannot be decrypted).
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

  /// The message content of a Markdown text. A link to a user (`[Name](https://matrix.to/#/@user:server)`, as the
  /// composer writes a mention) also lists that user in the intentional mentions, so they are notified.
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

  /// Logs why an SDK call failed (Debug builds only) and names the cause the room can show.
  private static func failure(_ operation: String, _ error: any Error) -> TimelineError {
    DebugLog.failure(operation, error)
    return TimelineErrorMapper.map(error)
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
private

  actor IndexRecorder
{
  private let index: MessageIndex
  private var recorded: [String: String] = [:]

  init(index: MessageIndex) {
    self.index = index
  }

  func record(roomId: String, items: [Domain.TimelineItem]) async {
    let (entries, redacted) = MessageIndex.entries(roomId: roomId, items: items)
    let changed = entries.filter { recorded[$0.eventId] != $0.text }
    let removed = redacted.filter { recorded[$0] != "" }
    for entry in changed { recorded[entry.eventId] = entry.text }
    for eventId in removed { recorded[eventId] = "" }
    await index.record(changed)
    await index.remove(eventIds: removed)
  }
}
final class SendHandles: @unchecked Sendable {
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

/// Queues the SDK's timeline diffs for `TimelineProxy` and `ActivityReactionsProxy`, in the order they arrive.
final class DiffListener: TimelineListener {
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
