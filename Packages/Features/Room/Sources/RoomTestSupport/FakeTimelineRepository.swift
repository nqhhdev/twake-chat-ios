import Domain
import Foundation

/// A hand-written `TimelineRepository` for tests (ADR 0010): records each call and answers with the scripted result.
/// `publish(_:)` sends a new list to the stream `open()` returned.
public final class FakeTimelineRepository: TimelineRepository, @unchecked Sendable {
  public enum Call: Equatable, Sendable {
    case open, loadOlder
    case send(String)
    case reply(String, String)
    case edit(String, String)
    case redact(String)
    case toggleReaction(String, String)
    case markAsRead, close
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
    return reachesStart
  }

  public func send(text: String) async throws(TimelineError) {
    record(.send(text))
    try actionResult.get()
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

  public func markAsRead() async { record(.markAsRead) }

  public func close() async {
    record(.close)
    finish()
  }
}
