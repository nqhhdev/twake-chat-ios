import Foundation
import Testing

@testable import MatrixData

struct StoreLockTimeoutTests {
  private struct LockTimedOut: Error {}
  private struct OtherFailure: Error {}

  private actor Attempts {
    private(set) var count = 0
    private(set) var pauses: [Duration] = []

    func next() -> Int {
      count += 1
      return count
    }

    func paused(_ pause: Duration) { pauses.append(pause) }
  }

  @Test func theEventCacheLockTimingOutIsToldApartFromOtherFailures() {
    #expect(
      StoreLock.isLockTimeout(
        .Generic(
          msg: "The lock couldn't be obtained after several attempts: locking has timed out",
          details: "EventCacheError(LockingStorage(Unobtained(TimedOut)))")))
    #expect(!StoreLock.isLockTimeout(.Generic(msg: "Room not found", details: nil)))
    #expect(
      !StoreLock.isLockTimeout(
        .MatrixApi(kind: .forbidden, code: "M_FORBIDDEN", msg: "", details: nil)))
    #expect(!StoreLock.isTimeout(OtherFailure()))
  }

  @Test func theLockIsWaitedForAtAQuarterSecondForAtMostTwentySeconds() {
    #expect(StoreLock.retryPause == .milliseconds(250))
    #expect(StoreLock.timeout == .seconds(20))
  }

  @Test func aTimedOutLockIsTriedAgainUntilItIsObtained() async throws {
    let attempts = Attempts()
    let value = try await StoreLock.retrying(
      isTimeout: { $0 is LockTimedOut }, sleep: { await attempts.paused($0) }
    ) {
      if await attempts.next() < 3 { throw LockTimedOut() }
      return "opened"
    }
    #expect(value == "opened")
    #expect(await attempts.count == 3)
    #expect(await attempts.pauses == [StoreLock.retryPause, StoreLock.retryPause])
  }

  @Test func anotherFailureIsNotTriedAgain() async {
    let attempts = Attempts()
    await #expect(throws: OtherFailure.self) {
      try await StoreLock.retrying(isTimeout: { $0 is LockTimedOut }, sleep: { _ in }) {
        _ = await attempts.next()
        throw OtherFailure()
      }
    }
    #expect(await attempts.count == 1)
  }

  @Test func theWaitEndsAtTheTimeoutWithTheLockError() async {
    let attempts = Attempts()
    await #expect(throws: LockTimedOut.self) {
      try await StoreLock.retrying(
        timeout: .milliseconds(60), pause: .milliseconds(20), isTimeout: { $0 is LockTimedOut }
      ) {
        _ = await attempts.next()
        throw LockTimedOut()
      }
    }
    let count = await attempts.count
    #expect(count >= 2)
    #expect(count <= 4)
  }

  @Test func aCancelledWaitStops() async {
    let task = Task {
      try await StoreLock.retrying(
        timeout: .seconds(30), pause: .milliseconds(10), isTimeout: { $0 is LockTimedOut }
      ) { () async throws -> Int in throw LockTimedOut() }
    }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
  }
}
