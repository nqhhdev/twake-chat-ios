import Domain
import Foundation
import RoomTestSupport
import Testing

@testable import Room

/// Reopening a chat where it was left (issue #138).
@MainActor
struct TimelineScrollMemoryTests {
  private let roomId = "!room:example.org"
  private let date = Date(timeIntervalSince1970: 1_700_000_000)

  private func item(_ id: String, event eventId: String) -> TimelineItem {
    TimelineItem(
      id: id,
      kind: .message(
        TimelineMessage(
          eventId: eventId, senderId: "@bob:example.org", senderName: "Bob", isOwn: false,
          date: date, body: .text("hello \(eventId)"))))
  }

  /// A chat opened with `memory`, showing `items`; finish its repository to close it.
  private func open(
    _ items: [TimelineItem], memory: TimelineScrollMemory?, pendingEventId: String? = nil
  ) async -> (RoomViewModel, FakeTimelineRepository, Task<Void, Never>) {
    let repository = FakeTimelineRepository()
    let viewModel = RoomViewModel(
      roomId: roomId, roomName: "Team", repository: repository, media: FakeMediaRepository(),
      scrollMemory: memory)
    viewModel.pendingEventId = pendingEventId
    let task = Task { await viewModel.start() }
    while !repository.calls.contains(.markAsRead) { await Task.yield() }
    repository.publish(items)
    while viewModel.state != .loaded(items) { await Task.yield() }
    return (viewModel, repository, task)
  }

  private func close(_ chat: (RoomViewModel, FakeTimelineRepository, Task<Void, Never>)) async {
    chat.1.finish()
    await chat.2.value
  }

  @Test func aChatLeftScrolledUpReopensOnTheSameMessage() async {
    let memory = TimelineScrollMemory()
    let first = await open(
      [item("a1", event: "$1"), item("a2", event: "$2"), item("a3", event: "$3")], memory: memory)
    first.0.rememberScroll(isAtBottom: false, topRowId: "a2")
    await close(first)
    #expect(memory.position(ofRoom: roomId) == .message(eventId: "$2"))

    // The timeline gives its rows new ids each time it opens; the message is found by its event.
    let second = await open(
      [item("b1", event: "$1"), item("b2", event: "$2"), item("b3", event: "$3")], memory: memory)
    #expect(second.0.restoreTarget == "b2")
    await close(second)
  }

  @Test func aChatLeftOnTheNewestMessageReopensThere() async {
    let memory = TimelineScrollMemory()
    let first = await open([item("a1", event: "$1"), item("a2", event: "$2")], memory: memory)
    first.0.rememberScroll(isAtBottom: true, topRowId: "a1")
    await close(first)
    #expect(memory.position(ofRoom: roomId) == .bottom)

    let second = await open([item("b1", event: "$1"), item("b2", event: "$2")], memory: memory)
    #expect(second.0.restoreTarget == nil)
    await close(second)
  }

  @Test func aDayDividerAtTheTopKeepsTheMessageUnderIt() async {
    let memory = TimelineScrollMemory()
    let divider = TimelineItem(id: "day", kind: .dayDivider(date))
    let chat = await open(
      [item("a1", event: "$1"), divider, item("a2", event: "$2")], memory: memory)
    chat.0.rememberScroll(isAtBottom: false, topRowId: "day")
    #expect(memory.position(ofRoom: roomId) == .message(eventId: "$2"))
    await close(chat)
  }

  @Test func aMessageNoLongerLoadedOpensOnTheNewestMessage() async {
    let memory = TimelineScrollMemory()
    memory.remember(.message(eventId: "$gone"), ofRoom: roomId)
    let chat = await open([item("b1", event: "$1")], memory: memory)
    #expect(chat.0.restoreTarget == nil)
    await close(chat)
  }

  @Test func aLinkToAMessageWinsOverWhereTheChatWasLeft() async {
    let memory = TimelineScrollMemory()
    memory.remember(.message(eventId: "$1"), ofRoom: roomId)
    let chat = await open(
      [item("b1", event: "$1"), item("b2", event: "$2")], memory: memory, pendingEventId: "$2")
    #expect(chat.0.restoreTarget == nil)
    await close(chat)
  }

  @Test func thePositionIsRestoredOnlyOnce() async {
    let memory = TimelineScrollMemory()
    memory.remember(.message(eventId: "$1"), ofRoom: roomId)
    let chat = await open([item("b1", event: "$1")], memory: memory)
    #expect(chat.0.restoreTarget == "b1")
    chat.0.restoreTarget = nil
    let more = [item("b1", event: "$1"), item("b2", event: "$2")]
    chat.1.publish(more)
    while chat.0.state != .loaded(more) { await Task.yield() }
    #expect(chat.0.restoreTarget == nil)
    await close(chat)
  }

  @Test func aChatWithoutMemoryKeepsNothing() async {
    let chat = await open([item("a1", event: "$1")], memory: nil)
    chat.0.rememberScroll(isAtBottom: false, topRowId: "a1")
    #expect(chat.0.restoreTarget == nil)
    await close(chat)
  }
}
