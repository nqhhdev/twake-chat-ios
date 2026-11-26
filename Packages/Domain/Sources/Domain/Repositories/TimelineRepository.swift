import Foundation

/// What the room screen needs from the data layer for one room: its timeline, kept up to date, and the actions on it.
/// Implemented in MatrixData; no SDK type appears here (ADR 0006). One instance serves one room.
public protocol TimelineRepository: Sendable {
  /// Opens the room's timeline and returns its items, oldest first. The stream yields the whole list again each time
  /// it changes and finishes when `close()` is called.
  func open() async throws(TimelineError) -> AsyncStream<[TimelineItem]>

  /// Loads older items. Returns `true` when the start of the room has been reached.
  func loadOlder() async throws(TimelineError) -> Bool

  /// Sends a text message, written in Markdown as the Flutter app's composer sends it.
  func send(text: String) async throws(TimelineError)

  /// Sends `text` as an emote (`m.emote`), which reads as a sentence about the sender: « Alice waves ».
  func send(emote text: String) async throws(TimelineError)

  /// Uploads and sends a picture, video, voice message or file; the timeline shows it as sending until it is done.
  func sendAttachment(_ attachment: OutgoingAttachment) async throws(TimelineError)

  /// Sends a poll (MSC3381).
  func createPoll(_ draft: PollDraft) async throws(TimelineError)

  /// Votes in the poll `pollEventId` for `answerIds`, replacing the user's earlier vote.
  func vote(_ answerIds: [String], in pollEventId: String) async throws(TimelineError)

  /// Ends the poll `pollEventId`: the results show to everyone and no one can vote any more.
  func endPoll(_ pollEventId: String) async throws(TimelineError)

  /// Tells the room the user is typing, or stopped.
  func setTyping(_ isTyping: Bool) async

  /// The names of the other members typing now, updated as they start and stop. Finishes when `close()` is called.
  func typingMembers() async -> AsyncStream<[String]>

  /// Sends a text message as a reply to the event `eventId`.
  func reply(text: String, to eventId: String) async throws(TimelineError)

  /// Replaces the text of the user's own message `eventId`.
  func edit(eventId: String, text: String) async throws(TimelineError)

  /// Deletes the message `eventId` for everyone.
  func redact(eventId: String) async throws(TimelineError)

  /// Adds the reaction `key` to the message `eventId`, or removes it when the user already sent it.
  func toggleReaction(_ key: String, on eventId: String) async throws(TimelineError)

  /// Pins the message `eventId` to the top of the room for everyone, or unpins it.
  func setPinned(_ pinned: Bool, eventId: String) async throws(TimelineError)

  /// The room's pinned messages, the most recently pinned last. Messages not loaded yet are left out.
  func pinnedMessages() async -> [TimelineMessage]

  /// Sends a copy of the message `eventId` (text, picture, file…) to the room `roomId`, without its reply.
  func forward(eventId: String, to roomId: String) async throws(TimelineError)

  /// The text the user left in the composer, kept by the SDK per room; `nil` when there is none.
  func loadDraft() async -> String?

  /// Keeps the composer's text for the next visit, or clears it when empty.
  func saveDraft(_ text: String) async

  /// Sends again the message of the local echo `transactionId` that failed to send. When the SDK paused the room's
  /// send queue (it does after a network failure), the queue starts again, which also sends what waits behind it.
  func retrySend(transactionId: String) async

  /// Retries decrypting events in this timeline that were previously un-decryptable. An empty `sessionIds` retries
  /// every such event, as the SDK and Element X do when the app becomes active and after keys are imported.
  func retryDecryption(sessionIds: [String]) async

  /// Removes the local echo `transactionId` of a message that is not sent yet, so it is never sent.
  func discardUnsent(transactionId: String) async throws(TimelineError)

  /// Reports the message `eventId` to the server's moderators, with an optional reason.
  func report(eventId: String, reason: String?) async throws(TimelineError)

  /// Hides everything from the user `userId` everywhere, as Matrix "ignore" does (the app calls it Block).
  func ignore(userId: String) async throws(TimelineError)

  /// Marks the room as read up to its latest event.
  func markAsRead() async

  /// Stops following the timeline. Safe when not opened.
  func close() async

  /// The emojis the user reacted with most recently, newest first, kept in the account data so every device shares
  /// them (`io.element.recent_emoji`).
  func recentReactions() async -> [String]

  /// Records a reaction the user sent, for `recentReactions()`.
  func addRecentReaction(_ key: String) async

  /// The room's members whose identity changed, updated as it changes. Finishes when the timeline closes.
  func identityWarnings() async -> AsyncStream<[IdentityWarning]>

  /// Accepts the new identity of a warning: pins it, or withdraws the old verification.
  func accept(_ warning: IdentityWarning) async throws(TimelineError)

  /// The commands the room's bots announce (MSC4332).
  func botCommands() async -> [BotCommand]

  func gifsEnabled() async -> Bool

  func stickerPacks() async -> [StickerPack]

  func emotes() async -> [Emote]

  func canSchedule() async -> Bool

  func schedule(text: String, at date: Date, replyTo: String?) async throws(ScheduleError)

  func scheduledMessages() async -> [ScheduledMessage]

  func cancelScheduled(id: String) async -> Bool

  func sendScheduledNow(id: String) async -> Bool

  func send(sticker: Sticker) async throws(TimelineError)

  /// Sends `text` as a message that runs `command`.
  func send(command: BotCommand, text: String) async throws(TimelineError)

  /// The versions of the message `eventId`, the original first (its `m.replace` edits, spec "Event replacements");
  /// in an encrypted room the device decrypts them. `nil` when they cannot be loaded.
  func editHistory(of eventId: String) async -> [MessageVersion]?

  /// The room's threads, the most recently active first (`/threads`); empty when it has none or they cannot load.
  func threads() async -> [ThreadListEntry]
}

/// One version of an edited message.
public struct MessageVersion: Sendable, Equatable, Identifiable {
  public let id: String
  public let text: String
  public let date: Date

  public init(id: String, text: String, date: Date) {
    self.id = id
    self.text = text
    self.date = date
  }

  /// The versions in an original event and its `m.replace` relations, as the client-server API returns them: the
  /// original's body, then each edit's `m.new_content` body, oldest first.
  public static func versions(original: Data?, relations: Data?) -> [MessageVersion] {
    func object(_ data: Data?) -> [String: Any]? {
      data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
    func version(_ event: [String: Any], body: String?) -> MessageVersion? {
      guard let id = event["event_id"] as? String, let body,
        let ts = event["origin_server_ts"] as? NSNumber
      else { return nil }
      return MessageVersion(
        id: id, text: body, date: Date(timeIntervalSince1970: ts.doubleValue / 1000))
    }
    var result: [MessageVersion] = []
    if let event = object(original),
      let first = version(event, body: (event["content"] as? [String: Any])?["body"] as? String)
    {
      result.append(first)
    }
    let edits = (object(relations)?["chunk"] as? [[String: Any]] ?? []).compactMap { event in
      let content = event["content"] as? [String: Any]
      return version(event, body: (content?["m.new_content"] as? [String: Any])?["body"] as? String)
    }
    return result + edits.sorted { $0.date < $1.date }
  }
}

/// A member of the room whose cryptographic identity changed since the user last accepted it (Element X
/// `IdentityStatusChange`): their messages may come from someone else until the user checks.
public struct IdentityWarning: Sendable, Equatable, Identifiable {
  public enum Kind: Sendable, Equatable {
    /// Their identity changed; accepting it pins the new one.
    case changed
    /// The identity the user had verified changed; withdrawing the verification accepts the new one.
    case verifiedChanged
  }

  public let userId: String
  public let name: String
  public let kind: Kind
  public var id: String { userId }

  public init(userId: String, name: String, kind: Kind) {
    self.userId = userId
    self.name = name
    self.kind = kind
  }
}

extension TimelineRepository {
  public func identityWarnings() async -> AsyncStream<[IdentityWarning]> {
    AsyncStream { $0.finish() }
  }
  public func accept(_ warning: IdentityWarning) async throws(TimelineError) {
    throw .requestFailed
  }
  public func botCommands() async -> [BotCommand] { [] }
  public func editHistory(of eventId: String) async -> [MessageVersion]? { nil }
  public func threads() async -> [ThreadListEntry] { [] }
  public func send(command: BotCommand, text: String) async throws(TimelineError) {
    throw .requestFailed
  }
  public func send(emote text: String) async throws(TimelineError) { throw .requestFailed }

  public func recentReactions() async -> [String] { [] }
  public func addRecentReaction(_ key: String) async {}
  public func gifsEnabled() async -> Bool { true }
  public func stickerPacks() async -> [StickerPack] { [] }
  public func emotes() async -> [Emote] { [] }
  public func canSchedule() async -> Bool { false }
  public func schedule(text: String, at date: Date, replyTo: String?) async throws(ScheduleError) {
    throw .unsupported
  }
  public func scheduledMessages() async -> [ScheduledMessage] { [] }
  public func cancelScheduled(id: String) async -> Bool { false }
  public func sendScheduledNow(id: String) async -> Bool { false }
  public func send(sticker: Sticker) async throws(TimelineError) { throw .requestFailed }
}

/// One thread of a room, as the room's Threads list shows it: its first message and its latest reply.
public struct ThreadListEntry: Sendable, Equatable, Identifiable {
  public var id: String { rootEventId }
  public let rootEventId: String
  public let rootSenderName: String
  public let rootText: String?
  public let date: Date
  public let replyCount: Int
  public let latestSenderName: String?
  public let latestText: String?
  /// When the latest reply was sent, or the root's date when it has none.
  public let latestDate: Date

  public init(
    rootEventId: String, rootSenderName: String, rootText: String?, date: Date, replyCount: Int,
    latestSenderName: String? = nil, latestText: String? = nil, latestDate: Date? = nil
  ) {
    self.rootEventId = rootEventId
    self.rootSenderName = rootSenderName
    self.rootText = rootText
    self.date = date
    self.replyCount = replyCount
    self.latestSenderName = latestSenderName
    self.latestText = latestText
    self.latestDate = latestDate ?? date
  }
}
