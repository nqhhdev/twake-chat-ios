import Domain
import Foundation
import RoomTestSupport
import Testing

@testable import Room

@MainActor
struct RoomLayoutStabilityTests {
  private func item(_ id: String) -> TimelineItem {
    TimelineItem(
      id: id,
      kind: .message(
        TimelineMessage(
          eventId: "$\(id)", senderId: "@bob:example.org", senderName: "Bob", isOwn: false,
          date: Date(timeIntervalSince1970: 1_700_000_000), body: .text("hello \(id)"))))
  }

  @Test func theHorizontalMetricsAreFixed() {
    #expect(RoomMetrics.gutter == 12)
    #expect(RoomMetrics.barInset == 16)
    #expect(RoomMetrics.avatarSize == 32)
    #expect(RoomMetrics.avatarSpacing == 8)
    #expect(RoomMetrics.avatarColumn == 40)
    #expect(RoomMetrics.bubbleInset == 12)
    #expect(RoomMetrics.capsuleInset == 12)
  }

  @Test func theTextWidthLeavesTheBubbleInsetsAndTheAvatarColumn() {
    #expect(RoomMetrics.contentWidth(bubbleWidth: 343, isOwn: true) == 319)
    #expect(RoomMetrics.contentWidth(bubbleWidth: 343, isOwn: false) == 279)
    #expect(RoomMetrics.contentWidth(bubbleWidth: 0, isOwn: false) == 0)
    #expect(RoomMetrics.reactionsWidth(bubbleWidth: 343, isOwn: false) == 303)
    #expect(RoomMetrics.reactionsWidth(bubbleWidth: 20, isOwn: false) == 0)
  }

  @Test func onlyANewMessageAtTheBottomAnimatesIn() {
    #expect(!RoomMetrics.animatesAppend(previousLastId: nil, rowIds: ["a", "b", "c"]))
    #expect(RoomMetrics.animatesAppend(previousLastId: "b", rowIds: ["a", "b", "c"]))
    #expect(!RoomMetrics.animatesAppend(previousLastId: "c", rowIds: ["a", "b", "c"]))
    #expect(!RoomMetrics.animatesAppend(previousLastId: "x", rowIds: ["a", "b", "c"]))
    #expect(
      !RoomMetrics.animatesAppend(previousLastId: "a", rowIds: ["a", "b", "c", "d", "e"]))
    #expect(RoomMetrics.animatesAppend(previousLastId: "a", rowIds: ["a", "b", "c", "d"]))
    #expect(!RoomMetrics.animatesAppend(previousLastId: "a", rowIds: []))
  }

  @Test func reopeningAChatKeepsItsMessagesUntilTheTimelineHasItemsAgain() async {
    let repository = FakeTimelineRepository()
    let viewModel = RoomViewModel(
      roomId: "!room:example.org", roomName: "Team", repository: repository,
      media: FakeMediaRepository())
    let first = Task { await viewModel.start() }
    while !repository.calls.contains(.markAsRead) { await Task.yield() }
    let shown = [item("1"), item("2")]
    repository.publish(shown)
    while viewModel.state != .loaded(shown) { await Task.yield() }
    repository.finish()
    await first.value

    let opens = repository.calls.filter { $0 == .open }.count
    let second = Task { await viewModel.start() }
    #expect(viewModel.state == .loaded(shown))
    while repository.calls.filter({ $0 == .open }).count == opens { await Task.yield() }
    repository.publish([])
    for _ in 0..<200 { await Task.yield() }
    #expect(viewModel.state == .loaded(shown))
    let next = [item("1"), item("2"), item("3")]
    repository.publish(next)
    while viewModel.state != .loaded(next) { await Task.yield() }
    #expect(viewModel.rows.count == 3)
    repository.finish()
    await second.value
  }

  @Test func aFirstOpenStillShowsLoadingThenAnEmptyTimeline() async {
    let repository = FakeTimelineRepository()
    let viewModel = RoomViewModel(
      roomId: "!room:example.org", roomName: "Team", repository: repository,
      media: FakeMediaRepository())
    let task = Task { await viewModel.start() }
    while !repository.calls.contains(.markAsRead) { await Task.yield() }
    #expect(viewModel.state == .loading)
    repository.publish([])
    while viewModel.state != .loaded([]) { await Task.yield() }
    repository.finish()
    await task.value
  }
}
