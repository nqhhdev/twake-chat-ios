import Domain
import Foundation
import RoomTestSupport
import Testing

@testable import Room

@MainActor
struct RoomViewModelTests {
  private let date = Date(timeIntervalSince1970: 1_700_000_000)

  private func message(_ id: String, own: Bool = false, text: String = "hello") -> TimelineMessage {
    TimelineMessage(
      eventId: id, senderId: own ? "@me:example.org" : "@bob:example.org",
      senderName: own ? "Me" : "Bob",
      isOwn: own, date: date, body: .text(text))
  }

  private func viewModel(_ repository: FakeTimelineRepository) -> RoomViewModel {
    RoomViewModel(roomId: "!room:example.org", roomName: "Team", repository: repository)
  }

  @Test func showsTheItemsTheRepositoryPublishesAndClosesWhenTheScreenGoes() async {
    let repository = FakeTimelineRepository()
    let viewModel = viewModel(repository)
    let task = Task { await viewModel.start() }
    while !repository.calls.contains(.markAsRead) { await Task.yield() }
    let item = TimelineItem(id: "1", kind: .message(message("$1")))
    repository.publish([item])
    while viewModel.state != .loaded([item]) { await Task.yield() }
    repository.finish()
    await task.value
    #expect(repository.calls.contains(.close))
  }

  @Test func aTimelineThatCannotOpenShowsAnError() async {
    let repository = FakeTimelineRepository()
    repository.openResult = .failure(.roomNotFound)
    let viewModel = viewModel(repository)
    await viewModel.start()
    #expect(viewModel.state == .failed("Could not open this chat."))
  }

  @Test func sendingClearsTheDraftAndSendsTrimmedText() async {
    let repository = FakeTimelineRepository()
    let viewModel = viewModel(repository)
    viewModel.draft = "  hi there \n"
    #expect(viewModel.canSend)
    await viewModel.send()
    #expect(repository.calls == [.send("hi there")])
    #expect(viewModel.draft.isEmpty)
  }

  @Test func aBlankDraftSendsNothing() async {
    let repository = FakeTimelineRepository()
    let viewModel = viewModel(repository)
    viewModel.draft = "   "
    #expect(!viewModel.canSend)
    await viewModel.send()
    #expect(repository.calls.isEmpty)
  }

  @Test func aFailedSendPutsTheDraftBack() async {
    let repository = FakeTimelineRepository()
    repository.actionResult = .failure(.requestFailed)
    let viewModel = viewModel(repository)
    viewModel.draft = "hi"
    await viewModel.send()
    #expect(viewModel.draft == "hi")
    #expect(viewModel.errorMessage != nil)
  }

  @Test func replyingSendsAReplyToTheMessage() async {
    let repository = FakeTimelineRepository()
    let viewModel = viewModel(repository)
    viewModel.reply(to: message("$1"))
    #expect(
      viewModel.composerMode == .reply(eventId: "$1", to: .init(senderName: "Bob", text: "hello")))
    viewModel.draft = "sure"
    await viewModel.send()
    #expect(repository.calls == [.reply("sure", "$1")])
    #expect(viewModel.composerMode == .new)
  }

  @Test func editingPutsTheTextInTheComposerAndSendsAnEdit() async {
    let repository = FakeTimelineRepository()
    let viewModel = viewModel(repository)
    viewModel.edit(message("$1", own: true, text: "typo"))
    #expect(viewModel.draft == "typo")
    viewModel.draft = "fixed"
    await viewModel.send()
    #expect(repository.calls == [.edit("$1", "fixed")])
  }

  @Test func onlyOwnMessagesCanBeEditedOrDeleted() async {
    let repository = FakeTimelineRepository()
    let viewModel = viewModel(repository)
    viewModel.edit(message("$1"))
    #expect(viewModel.composerMode == .new)
    await viewModel.delete(message("$1"))
    #expect(repository.calls.isEmpty)
    await viewModel.delete(message("$2", own: true))
    #expect(repository.calls == [.redact("$2")])
  }

  @Test func cancellingAnEditClearsTheDraft() {
    let viewModel = viewModel(FakeTimelineRepository())
    viewModel.edit(message("$1", own: true, text: "typo"))
    viewModel.cancelComposerMode()
    #expect(viewModel.draft.isEmpty)
    #expect(viewModel.composerMode == .new)
  }

  @Test func reactingTogglesTheReaction() async {
    let repository = FakeTimelineRepository()
    let viewModel = viewModel(repository)
    await viewModel.toggleReaction("👍", on: message("$1"))
    #expect(repository.calls == [.toggleReaction("👍", "$1")])
  }

  @Test func loadingOlderStopsAtTheStartOfTheRoom() async {
    let repository = FakeTimelineRepository()
    repository.reachesStart = true
    let viewModel = viewModel(repository)
    await viewModel.loadOlder()
    #expect(viewModel.reachedStart)
    await viewModel.loadOlder()
    #expect(repository.calls == [.loadOlder])
  }

  @Test func dayTitlesSayTodayAndYesterday() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(RoomViewModel.dayTitle(now, now: now) == "Today")
    #expect(RoomViewModel.dayTitle(now.addingTimeInterval(-86_400), now: now) == "Yesterday")
  }
}
