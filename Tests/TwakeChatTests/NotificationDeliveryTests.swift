import Foundation
import Testing
import UserNotifications

@testable import TwakeChat

struct NotificationDeliveryTests {
  private final class Record: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    private var completedOnMain: Bool?

    func note(_ event: String) { lock.withLock { events.append(event) } }
    func completed(onMain: Bool) {
      lock.withLock {
        events.append("completed")
        completedOnMain = onMain
      }
    }
    var log: [String] { lock.withLock { events } }
    var mainThreadCompletion: Bool? { lock.withLock { completedOnMain } }
  }

  private static func isMainThread() -> Bool { Thread.isMainThread }

  private static let tap = NotificationAction(
    actionIdentifier: UNNotificationDefaultActionIdentifier, userText: nil,
    userInfo: ["room_id": "!room:example.org", "event_id": "$event"], title: "Alice")

  private static func deliverFromABackgroundQueue(
    _ action: NotificationAction?, into record: Record
  )
    async
  {
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
      DispatchQueue.global(qos: .userInitiated).async {
        AppDelegate.deliver(
          action,
          to: { handled in
            record.note("handled \(handled.roomId) main=\(Self.isMainThread())")
          },
          then: {
            record.completed(onMain: Thread.isMainThread)
            done.resume()
          })
      }
    }
  }

  @Test func aTapDeliveredOffTheMainThreadIsHandledOnTheMainActorThenCompletedOnTheMainThread()
    async throws
  {
    let action = try #require(Self.tap)
    let record = Record()
    await Self.deliverFromABackgroundQueue(action, into: record)
    #expect(record.log == ["handled !room:example.org main=true", "completed"])
    #expect(record.mainThreadCompletion == true)
  }

  @Test func aResponseThatIsNoActionStillCompletesOnTheMainThread() async {
    let record = Record()
    await Self.deliverFromABackgroundQueue(nil, into: record)
    #expect(record.log == ["completed"])
    #expect(record.mainThreadCompletion == true)
  }

  @MainActor @Test func theCompletionGivenToUIKitRunsOnTheMainActor() async {
    let record = Record()
    let completion = MainThreadCompletion<Int> { value in
      record.note("value \(value)")
      record.completed(onMain: Thread.isMainThread)
    }
    await Task.detached { await completion.call(7) }.value
    #expect(record.log == ["value 7", "completed"])
    #expect(record.mainThreadCompletion == true)
  }
}
