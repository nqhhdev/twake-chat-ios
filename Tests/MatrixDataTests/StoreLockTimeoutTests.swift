import Foundation
import Testing

@testable import MatrixData

struct StoreLockTimeoutTests {
  @Test func theEventCacheLockTimingOutIsToldApartFromOtherFailures() {
    #expect(
      TimelineProxy.isStoreLockTimeout(
        .Generic(
          msg: "The lock couldn't be obtained after several attempts: locking has timed out",
          details: "EventCacheError(LockingStorage(Unobtained(TimedOut)))")))
    #expect(!TimelineProxy.isStoreLockTimeout(.Generic(msg: "Room not found", details: nil)))
    #expect(
      !TimelineProxy.isStoreLockTimeout(
        .MatrixApi(kind: .forbidden, code: "M_FORBIDDEN", msg: "", details: nil)))
  }
}
