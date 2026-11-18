import Domain
import Foundation

/// A hand-written `TimelineRepository` for tests (ADR 0010): records each call and answers with the scripted result.
/// `publish(_:)` sends a new list to the stream `open()` returned.
public final class FakeTimelineRepository: TimelineRepository, @unchecked Sendable {
  public enum Call: Equatable, Sendable {
    case open, loadOlder
    case send(String)
    case emote(String)
    case reply(String, String)
    case edit(String, String)
    case redact(String)
    case toggleReaction(String, String)
    case markAsRead, close
    case attachment(OutgoingAttachment)
    case typing(Bool)
    case pin(Bool, String)
    case forward(String, String)
    case report(String, String?)
    case retry(String)
    case retryDecryption([String])
    case discard(String)
    case ignore(String)
    case createPoll(PollDraft)
    case vote([String], String)
    case endPoll(String)
    case acceptIdentity(String)
    case command(String, String)
  }

  /// What `botCommands()` answers.
  public var commands: [BotCommand] {
    get { lock.withLock { _commands } }
    set { lock.withLock { _commands = newValue } }
  }
  private var _commands: [BotCommand] = []

  public func botCommands() async -> [BotCommand] { commands }

  /// What `threads()` answers.
  public var threadEntries: [ThreadListEntry] {
    get { lock.withLock { _threadEntries } }
    set { lock.withLock { _threadEntries = newValue } }
  }
  private var _threadEntries: [ThreadListEntry] = []

  public func threads() async -> [ThreadListEntry] { threadEntries }

  public func send(command: BotCommand, text: String) async throws(TimelineError) {
    record(.command(command.name, text))
    try actionResult.get()
  }

  private let lock = NSLock()
  private var _calls: [Call] = []
  private var _openResult: Result<Void, TimelineError> = .success(())
  private var _actionResult: Result<Void, TimelineError> = .success(())
  private var _reachesStart = false
  private var continuation: AsyncStream<[TimelineItem]>.Continuation?

  public init() {}

  public var calls: [Call] { lock.withLock { _calls } }

  public var openResult: Result<Void, TimelineError> {
    get { lock.withLock { _openResult } }
    set { lock.withLock { _openResult = newValue } }
  }

  /// What send, reply, edit, redact and toggleReaction throw, if anything.
  public var actionResult: Result<Void, TimelineError> {
    get { lock.withLock { _actionResult } }
    set { lock.withLock { _actionResult = newValue } }
  }

  /// How long a page takes, for a slow server.
  public var loadOlderDelay: Duration = .zero

  /// What `loadOlder` returns.
  public var reachesStart: Bool {
    get { lock.withLock { _reachesStart } }
    set { lock.withLock { _reachesStart = newValue } }
  }

  public func publish(_ items: [TimelineItem]) {
    let continuation = lock.withLock { self.continuation }
    continuation?.yield(items)
  }

  public func finish() {
    let continuation = lock.withLock { self.continuation }
    continuation?.finish()
  }

  private func record(_ call: Call) {
    lock.withLock { _calls.append(call) }
  }

  public func open() async throws(TimelineError) -> AsyncStream<[TimelineItem]> {
    record(.open)
    try openResult.get()
    let (stream, continuation) = AsyncStream<[TimelineItem]>.makeStream()
    lock.withLock { self.continuation = continuation }
    return stream
  }

  public func loadOlder() async throws(TimelineError) -> Bool {
    record(.loadOlder)
    let delay = lock.withLock { loadOlderDelay }
    if delay > .zero { try? await Task.sleep(for: delay) }
    return reachesStart
  }

  public func send(text: String) async throws(TimelineError) {
    record(.send(text))
    try actionResult.get()
  }

  public func sendAttachment(_ attachment: OutgoingAttachment) async throws(TimelineError) {
    record(.attachment(attachment))
    try actionResult.get()
  }

  public func setTyping(_ isTyping: Bool) async { record(.typing(isTyping)) }

  private var _pinned: [TimelineMessage] = []

  /// What `pinnedMessages()` returns.
  public var pinned: [TimelineMessage] {
    get { lock.withLock { _pinned } }
    set { lock.withLock { _pinned = newValue } }
  }

  public func setPinned(_ pinned: Bool, eventId: String) async throws(TimelineError) {
    record(.pin(pinned, eventId))
    try actionResult.get()
  }

  public func pinnedMessages() async -> [TimelineMessage] { pinned }

  private var _draft: String?

  /// The draft the fake keeps.
  public var draft: String? {
    get { lock.withLock { _draft } }
    set { lock.withLock { _draft = newValue } }
  }

  public func loadDraft() async -> String? { draft }
  public func saveDraft(_ text: String) async { draft = text.isEmpty ? nil : text }

  public func forward(eventId: String, to roomId: String) async throws(TimelineError) {
    record(.forward(eventId, roomId))
    try actionResult.get()
  }

  private var typingContinuation: AsyncStream<[String]>.Continuation?

  /// Whether someone follows `typingMembers()`; a test waits for it before it publishes.
  public var isFollowingTyping: Bool { lock.withLock { typingContinuation != nil } }

  /// Sends the names typing now to the stream `typingMembers()` returned.
  public func publishTyping(_ names: [String]) {
    let continuation = lock.withLock { typingContinuation }
    continuation?.yield(names)
  }

  public func typingMembers() async -> AsyncStream<[String]> {
    let (stream, continuation) = AsyncStream<[String]>.makeStream()
    lock.withLock { typingContinuation = continuation }
    return stream
  }

  public func reply(text: String, to eventId: String) async throws(TimelineError) {
    record(.reply(text, eventId))
    try actionResult.get()
  }

  public func edit(eventId: String, text: String) async throws(TimelineError) {
    record(.edit(eventId, text))
    try actionResult.get()
  }

  public func redact(eventId: String) async throws(TimelineError) {
    record(.redact(eventId))
    try actionResult.get()
  }

  public func toggleReaction(_ key: String, on eventId: String) async throws(TimelineError) {
    record(.toggleReaction(key, eventId))
    try actionResult.get()
  }

  public func send(emote text: String) async throws(TimelineError) {
    record(.emote(text))
    try actionResult.get()
  }

  public func retrySend(transactionId: String) async { record(.retry(transactionId)) }

  public func retryDecryption(sessionIds: [String]) async { record(.retryDecryption(sessionIds)) }

  public func discardUnsent(transactionId: String) async throws(TimelineError) {
    record(.discard(transactionId))
    try actionResult.get()
  }

  public func createPoll(_ draft: PollDraft) async throws(TimelineError) {
    record(.createPoll(draft))
    try actionResult.get()
  }

  public func vote(_ answerIds: [String], in pollEventId: String) async throws(TimelineError) {
    record(.vote(answerIds, pollEventId))
    try actionResult.get()
  }

  public func accept(_ warning: IdentityWarning) async throws(TimelineError) {
    record(.acceptIdentity(warning.userId))
    try actionResult.get()
  }

  public func endPoll(_ pollEventId: String) async throws(TimelineError) {
    record(.endPoll(pollEventId))
    try actionResult.get()
  }

  public func report(eventId: String, reason: String?) async throws(TimelineError) {
    record(.report(eventId, reason))
    try actionResult.get()
  }

  public func ignore(userId: String) async throws(TimelineError) {
    record(.ignore(userId))
    try actionResult.get()
  }

  public func markAsRead() async { record(.markAsRead) }

  public func close() async {
    record(.close)
    finish()
  }
}
