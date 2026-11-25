import Domain
import Foundation
import RoomTestSupport
import SwiftUI
import Testing

@testable import Room

@MainActor
struct ComposerKeysTests {
  private let date = Date(timeIntervalSince1970: 1_700_000_000)

  private func message(_ id: String, own: Bool, body: TimelineMessage.Body = .text("hello"))
    -> TimelineItem
  {
    TimelineItem(
      id: id,
      kind: .message(
        TimelineMessage(
          eventId: id, senderId: own ? "@me:example.org" : "@bob:example.org",
          senderName: own ? "Me" : "Bob", isOwn: own, date: date, body: body)))
  }

  private func loaded(_ items: [TimelineItem]) async -> (
    RoomViewModel, FakeTimelineRepository, Task<Void, Never>
  ) {
    let repository = FakeTimelineRepository()
    let viewModel = RoomViewModel(
      roomId: "!room:example.org", roomName: "Team", repository: repository,
      media: FakeMediaRepository())
    let task = Task { await viewModel.start() }
    while !repository.calls.contains(.markAsRead) { await Task.yield() }
    repository.publish(items)
    while viewModel.state != .loaded(items) { await Task.yield() }
    return (viewModel, repository, task)
  }

  @Test func returnSendsAndShiftOrOptionReturnWritesANewLine() {
    #expect(ComposerKey(.return, modifiers: []) == .send)
    #expect(ComposerKey(.return, modifiers: .capsLock) == .send)
    #expect(ComposerKey(.return, modifiers: .shift) == .newLine)
    #expect(ComposerKey(.return, modifiers: .option) == .newLine)
    #expect(ComposerKey(.return, modifiers: .command) == nil)
    #expect(ComposerKey(.upArrow, modifiers: []) == .editLast)
    #expect(ComposerKey(.upArrow, modifiers: .shift) == nil)
    #expect(ComposerKey(.escape, modifiers: []) == .cancel)
    #expect(ComposerKey(.space, modifiers: []) == nil)
  }

  @Test func returnSendsTheDraft() async {
    let (viewModel, repository, task) = await loaded([])
    viewModel.draft = "Hi"
    #expect(viewModel.handle(.send))
    while !repository.calls.contains(.send("Hi")) { await Task.yield() }
    #expect(viewModel.draft.isEmpty)
    repository.finish()
    await task.value
  }

  @Test func returnOnAnEmptyDraftSendsNothingAndWritesNoNewLine() async {
    let (viewModel, repository, task) = await loaded([])
    viewModel.draft = "  "
    #expect(viewModel.handle(.send))
    #expect(!viewModel.handle(.newLine))
    #expect(!repository.calls.contains { if case .send = $0 { true } else { false } })
    repository.finish()
    await task.value
  }

  @Test func upInAnEmptyComposerEditsTheLastOwnTextMessage() async {
    let items = [
      message("$1", own: true, body: .text("first")),
      message("$2", own: true, body: .text("second")),
      message("$3", own: true, body: .image(caption: nil)),
      message("$4", own: false),
    ]
    let (viewModel, repository, task) = await loaded(items)
    #expect(viewModel.handle(.editLast))
    #expect(viewModel.composerMode == .edit(eventId: "$2"))
    #expect(viewModel.draft == "second")
    repository.finish()
    await task.value
  }

  @Test func upWithTextOrWithoutAnOwnMessageMovesTheCaret() async {
    let (viewModel, repository, task) = await loaded([message("$1", own: false)])
    #expect(!viewModel.handle(.editLast))
    #expect(viewModel.composerMode == .new)
    viewModel.draft = "typing"
    #expect(!viewModel.handle(.editLast))
    repository.finish()
    await task.value
  }

  @Test func escapeCancelsAReplyOrAnEditOnly() async {
    let own = message("$1", own: true, body: .text("mine"))
    let (viewModel, repository, task) = await loaded([own])
    #expect(!viewModel.handle(.cancel))
    _ = viewModel.handle(.editLast)
    #expect(viewModel.handle(.cancel))
    #expect(viewModel.composerMode == .new)
    #expect(viewModel.draft.isEmpty)
    if case .message(let mine) = own.kind { viewModel.reply(to: mine) }
    #expect(viewModel.handle(.cancel))
    #expect(viewModel.composerMode == .new)
    repository.finish()
    await task.value
  }
}
