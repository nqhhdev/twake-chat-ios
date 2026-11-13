import Domain
import Foundation

/// A hand-written `RoomListRepository` for tests (ADR 0010: fakes, no mocking library). `start()` answers with the
/// scripted error, or with a stream the test feeds through `send(_:)` and ends through `finish()` or `stop()`.
public final class FakeRoomListRepository: RoomListRepository, @unchecked Sendable {
  private let lock = NSLock()
  private var _startError: RoomListError?
  private var _continuation: AsyncStream<[RoomSummary]>.Continuation?
  private var _startCallCount = 0
  private var _stopCallCount = 0

  public init() {}

  /// When set, `start()` throws it.
  public var startError: RoomListError? {
    get { lock.withLock { _startError } }
    set { lock.withLock { _startError = newValue } }
  }

  public var startCallCount: Int { lock.withLock { _startCallCount } }
  public var stopCallCount: Int { lock.withLock { _stopCallCount } }

  /// True once `start()` returned a stream that has not ended.
  public var isStarted: Bool { lock.withLock { _continuation != nil } }

  /// Publishes a room list on the started stream.
  public func send(_ rooms: [RoomSummary]) {
    _ = lock.withLock { _continuation }?.yield(rooms)
  }

  /// Ends the started stream, as the SDK list ending would.
  public func finish() {
    let continuation = lock.withLock {
      defer { _continuation = nil }
      return _continuation
    }
    continuation?.finish()
  }

  public func start() async throws(RoomListError) -> AsyncStream<[RoomSummary]> {
    let error = lock.withLock {
      _startCallCount += 1
      return _startError
    }
    if let error { throw error }
    finish()
    let (stream, continuation) = AsyncStream<[RoomSummary]>.makeStream()
    lock.withLock { _continuation = continuation }
    return stream
  }

  public func stop() async {
    lock.withLock { _stopCallCount += 1 }
    finish()
  }
}
