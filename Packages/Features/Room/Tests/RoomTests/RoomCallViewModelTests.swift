import Domain
import Foundation
import Testing

@testable import Room

private let hangUpMessage = #"{"api":"fromWidget","action":"im.vector.hangup","data":{}}"#
private let closeMessage = #"{"api":"fromWidget","action":"io.element.close","data":{}}"#
private let joinedMessage = #"{"api":"fromWidget","action":"io.element.join","data":{}}"#

@MainActor
struct RoomCallViewModelTests {
  private final class FakeSession: CallWidgetSession, @unchecked Sendable {
    let url = URL(string: "https://call.example.org/room")!
    let userId = "@me:example.org"
    private(set) var received: [String] = []
    private(set) var ended = false

    func messagesToWidget() async -> AsyncStream<String> { AsyncStream { $0.finish() } }
    func receiveFromWidget(_ message: String) async { received.append(message) }
    func end() async { ended = true }
  }

  private actor FakeCalls: RoomCallRepository {
    var available = true
    var failure: RoomCallError?
    var states: [RoomCallState] = []
    private(set) var opened: [CallIntent] = []
    let session = FakeSession()

    init(available: Bool = true, failure: RoomCallError? = nil, states: [RoomCallState] = []) {
      self.available = available
      self.failure = failure
      self.states = states
    }

    func isAvailable() async -> Bool { available }

    func callStates(roomId: String) async -> AsyncStream<RoomCallState> {
      let states = states
      return AsyncStream { continuation in
        for state in states { continuation.yield(state) }
        continuation.finish()
      }
    }

    func open(roomId: String, intent: CallIntent) async throws(RoomCallError)
      -> any CallWidgetSession
    {
      opened.append(intent)
      if let failure { throw failure }
      return session
    }
  }

  private final class FakeSystem: CallSystemReporting {
    var onEndedBySystem: (@MainActor (UUID) -> Void)?
    private(set) var events: [String] = []

    func reportStarted(_ id: UUID, title: String) async { events.append("started \(title)") }
    func reportConnected(_ id: UUID) { events.append("connected") }
    func reportEnded(_ id: UUID) async { events.append("ended") }
  }

  private static let active = RoomCallState(isActive: true, participants: ["@bob:example.org"])

  @Test func callsAreHiddenWhenTheServerHasNoFocus() async {
    let viewModel = RoomCallViewModel(
      roomId: "!r", repository: FakeCalls(available: false), center: CallCenter())
    await viewModel.load()
    #expect(!viewModel.isAvailable)
    await viewModel.open(title: "Room")
    #expect(viewModel.activeCall == nil)
  }

  @Test func startingWithNoCallStartsOneAndReportsIt() async {
    let calls = FakeCalls()
    let system = FakeSystem()
    let viewModel = RoomCallViewModel(
      roomId: "!r", repository: calls, system: system, center: CallCenter())
    await viewModel.load()
    #expect(viewModel.actionTitle == "Start call")
    await viewModel.open(title: "Room")
    #expect(await calls.opened == [.start])
    #expect(viewModel.activeCall?.url.absoluteString == "https://call.example.org/room")
    #expect(system.events == ["started Room"])
  }

  @Test func anActiveCallIsJoined() async {
    let calls = FakeCalls(states: [Self.active])
    let viewModel = RoomCallViewModel(
      roomId: "!r", repository: calls, center: CallCenter())
    await viewModel.load()
    await viewModel.watch()
    #expect(viewModel.state == Self.active)
    #expect(viewModel.actionTitle == "Join call")
    #expect(viewModel.participantCount == 1)
    await viewModel.open(title: "Room")
    #expect(await calls.opened == [.join])
  }

  @Test func widgetMessagesGoToTheDriverAndJoiningConnects() async {
    let calls = FakeCalls()
    let system = FakeSystem()
    let viewModel = RoomCallViewModel(
      roomId: "!r", repository: calls, system: system, center: CallCenter())
    await viewModel.load()
    await viewModel.open(title: "Room")
    await viewModel.fromWidget(joinedMessage)
    #expect(calls.session.received == [joinedMessage])
    #expect(system.events == ["started Room", "connected"])
    #expect(viewModel.activeCall != nil)
  }

  @Test(arguments: [hangUpMessage, closeMessage])
  func hangingUpInTheWidgetEndsTheCall(_ message: String) async {
    let calls = FakeCalls()
    let system = FakeSystem()
    let viewModel = RoomCallViewModel(
      roomId: "!r", repository: calls, system: system, center: CallCenter())
    await viewModel.load()
    await viewModel.open(title: "Room")
    await viewModel.fromWidget(message)
    #expect(calls.session.received == [message])
    #expect(calls.session.ended)
    #expect(viewModel.activeCall == nil)
    #expect(system.events == ["started Room", "ended"])
  }

  @Test(.timeLimit(.minutes(1))) func endingFromTheSystemClosesTheCall() async {
    let calls = FakeCalls()
    let system = FakeSystem()
    let viewModel = RoomCallViewModel(
      roomId: "!r", repository: calls, system: system, center: CallCenter())
    await viewModel.load()
    await viewModel.open(title: "Room")
    guard let id = viewModel.activeCall?.id else {
      Issue.record("No call was opened")
      return
    }
    system.onEndedBySystem?(id)
    while !calls.session.ended || system.events.last != "ended" { await Task.yield() }
    #expect(viewModel.activeCall == nil)
    #expect(system.events == ["started Room", "ended"])
  }

  @Test(arguments: [
    (RoomCallError.notAllowed, "You may not join a call in this chat."),
    (RoomCallError.notJoined, "You are no longer in this chat."),
    (RoomCallError.failed, "The call could not be started. Please try again."),
    (RoomCallError.unavailable, "The call could not be started. Please try again."),
  ])
  func aFailedOpenSaysWhy(_ failure: RoomCallError, _ message: String) async {
    let viewModel = RoomCallViewModel(
      roomId: "!r", repository: FakeCalls(failure: failure), center: CallCenter())
    await viewModel.load()
    await viewModel.open(title: "Room")
    #expect(viewModel.activeCall == nil)
    #expect(viewModel.errorMessage == message)
  }

  @Test func onlyWidgetRequestsCount() {
    #expect(CallWidgetAction.isHangUp(hangUpMessage))
    #expect(!CallWidgetAction.isHangUp(#"{"api":"toWidget","action":"im.vector.hangup"}"#))
    #expect(!CallWidgetAction.isHangUp("not json"))
    #expect(CallWidgetAction.isJoined(joinedMessage))
    #expect(!CallWidgetAction.isJoined(hangUpMessage))
  }

  @Test func theCallOutlivesTheRoomScreenAndComesBackFromIt() async {
    let center = CallCenter()
    let system = FakeSystem()
    let first = RoomCallViewModel(
      roomId: "!r", repository: FakeCalls(), system: system, center: center)
    await first.load()
    await first.open(title: "Room")
    let call = first.activeCall
    #expect(call != nil)
    center.minimize()
    #expect(center.isMinimized)

    let reopened = RoomCallViewModel(
      roomId: "!r", repository: FakeCalls(), system: system, center: center)
    await reopened.load()
    #expect(reopened.activeCall === call)
    await reopened.open(title: "Room")
    #expect(!center.isMinimized)
    #expect(center.call === call)
  }

  @Test func anotherRoomDoesNotSeeTheCall() async {
    let center = CallCenter()
    let room = RoomCallViewModel(roomId: "!r", repository: FakeCalls(), center: center)
    await room.load()
    await room.open(title: "Room")
    let other = RoomCallViewModel(roomId: "!other", repository: FakeCalls(), center: center)
    #expect(other.activeCall == nil)
    #expect(center.roomId == "!r")
  }

  @Test func aCallInAnotherRoomEndsTheFirstOne() async {
    let center = CallCenter()
    let first = RoomCallViewModel(roomId: "!r", repository: FakeCalls(), center: center)
    await first.load()
    await first.open(title: "Room")
    let firstCall = first.activeCall
    let second = RoomCallViewModel(roomId: "!other", repository: FakeCalls(), center: center)
    await second.load()
    await second.open(title: "Other")
    #expect(firstCall?.hasEnded == true)
    #expect(center.roomId == "!other")
    #expect(first.activeCall == nil)
  }

  @Test func endingClearsTheCallAndTheMinimizedState() async {
    let center = CallCenter()
    let room = RoomCallViewModel(roomId: "!r", repository: FakeCalls(), center: center)
    await room.load()
    await room.open(title: "Room")
    center.minimize()
    await center.end()
    #expect(center.call == nil)
    #expect(!center.isMinimized)
    #expect(room.activeCall == nil)
  }

  @Test func minimizingWithoutACallDoesNothing() {
    let center = CallCenter()
    center.minimize()
    #expect(!center.isMinimized)
  }
}
