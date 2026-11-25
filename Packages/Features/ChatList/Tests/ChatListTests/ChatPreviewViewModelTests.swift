import ChatListTestSupport
import Domain
import Foundation
import Testing

@testable import ChatList

/// A long press on a chat shows its latest messages, read-only: the timeline opens while the preview shows, never
/// marks the chat as read, and closes with the preview.
@MainActor
struct ChatPreviewViewModelTests {
  /// Records the calls the preview makes; every other action of the timeline is not expected and does nothing.
  private actor Timeline: TimelineRepository {
    enum Call: Equatable { case open, loadOlder, close, markAsRead }
    private(set) var calls: [Call] = []
    var opens = true
    nonisolated let items: AsyncStream<[TimelineItem]>
    nonisolated let publish: AsyncStream<[TimelineItem]>.Continuation

    init() { (items, publish) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1)) }

    func failOpening() { opens = false }

    func open() async throws(TimelineError) -> AsyncStream<[TimelineItem]> {
      calls.append(.open)
      guard opens else { throw .unavailable }
      return items
    }
    func loadOlder() async throws(TimelineError) -> Bool {
      calls.append(.loadOlder)
      return false
    }
    func close() async {
      calls.append(.close)
      publish.finish()
    }
    func markAsRead() async { calls.append(.markAsRead) }

    func send(text: String) async throws(TimelineError) {}
    func send(emote text: String) async throws(TimelineError) {}
    func sendAttachment(_ attachment: OutgoingAttachment) async throws(TimelineError) {}
    func createPoll(_ draft: PollDraft) async throws(TimelineError) {}
    func vote(_ answerIds: [String], in pollEventId: String) async throws(TimelineError) {}
    func endPoll(_ pollEventId: String) async throws(TimelineError) {}
    func setTyping(_ isTyping: Bool) async {}
    func typingMembers() async -> AsyncStream<[String]> { AsyncStream { $0.finish() } }
    func reply(text: String, to eventId: String) async throws(TimelineError) {}
    func edit(eventId: String, text: String) async throws(TimelineError) {}
    func redact(eventId: String) async throws(TimelineError) {}
    func toggleReaction(_ key: String, on eventId: String) async throws(TimelineError) {}
    func setPinned(_ pinned: Bool, eventId: String) async throws(TimelineError) {}
    func pinnedMessages() async -> [TimelineMessage] { [] }
    func forward(eventId: String, to roomId: String) async throws(TimelineError) {}
    func loadDraft() async -> String? { nil }
    func saveDraft(_ text: String) async {}
    func retrySend(transactionId: String) async {}
    func retryDecryption(sessionIds: [String]) async {}
    func discardUnsent(transactionId: String) async throws(TimelineError) {}
    func report(eventId: String, reason: String?) async throws(TimelineError) {}
    func ignore(userId: String) async throws(TimelineError) {}
    func recentReactions() async -> [String] { [] }
    func addRecentReaction(_ key: String) async {}
    func identityWarnings() async -> AsyncStream<[IdentityWarning]> { AsyncStream { $0.finish() } }
    func accept(_ warning: IdentityWarning) async throws(TimelineError) {}
    func botCommands() async -> [BotCommand] { [] }
    func send(command: BotCommand, text: String) async throws(TimelineError) {}
    func editHistory(of eventId: String) async -> [MessageVersion]? { nil }
    func threads() async -> [ThreadListEntry] { [] }
  }

  private let room = RoomSummary(
    id: "!team", name: "Team", lastMessageText: "Hi", lastMessageSender: "Alice", lastActivity: nil)

  private func message(
    _ id: String, _ body: TimelineMessage.Body, own: Bool = false,
    visibility: TimelineItem.Visibility = .always
  ) -> TimelineItem {
    TimelineItem(
      id: id,
      kind: .message(
        TimelineMessage(
          eventId: id, senderId: own ? "@me" : "@alice", senderName: own ? "Me" : "Alice",
          isOwn: own, date: Date(timeIntervalSince1970: 0), body: body)),
      visibility: visibility)
  }

  private func waitUntil(_ condition: () async -> Bool) async {
    for _ in 0..<10_000 {
      if await condition() { return }
      await Task.yield()
    }
  }

  @Test func showsTheLatestMessagesNewestLastAndLeavesRoomEventsOut() {
    var items = [TimelineItem(id: "start", kind: .timelineStart)]
    items += (1...8).map { message("m\($0)", .text("Message \($0)")) }
    items.append(TimelineItem(id: "join", kind: .stateNotice("Bob joined")))
    items.append(message("hidden", .unsupported, visibility: .unknown))

    let lines = ChatPreviewViewModel.lines(items)

    #expect(lines.map(\.id) == ["m3", "m4", "m5", "m6", "m7", "m8"])
    #expect(lines.last?.text == "Message 8")
  }

  @Test func undecryptableAndDeletedMessagesShowTheTimelinePlaceholders() {
    let lines = ChatPreviewViewModel.lines([
      message("e", .unableToDecrypt(.unknown)), message("d", .redacted, own: true),
      message("p", .image(caption: nil)),
    ])

    #expect(lines[0].text == "This message cannot be read on this device yet.")
    #expect(lines[0].isPlaceholder)
    #expect(lines[1].text == "This message has been deleted")
    #expect(lines[1].isOwn)
    #expect(lines[2].text == "Picture")
    #expect(lines[2].systemImage == "photo")
    #expect(!lines[2].isPlaceholder)
  }

  @Test func followsTheTimelineWithoutMarkingReadAndClosesItWhenThePreviewCloses() async {
    let timeline = Timeline()
    let preview = ChatPreviewViewModel(room: room, repository: timeline)
    let task = Task { await preview.run() }

    // The empty list the timeline publishes first keeps the preview loading.
    timeline.publish.yield([])
    await waitUntil { await timeline.calls.contains(.open) }
    #expect(preview.state == .loading)

    timeline.publish.yield([
      TimelineItem(id: "start", kind: .timelineStart), message("a", .text("Hi")),
    ])
    await waitUntil { preview.state != .loading }
    #expect(preview.state.lines?.map(\.text) == ["Hi"])

    task.cancel()
    await task.value
    let calls = await timeline.calls
    #expect(calls == [.open, .close])
  }

  @Test func loadsOneOlderPageWhenTooFewMessagesAreLoaded() async {
    let timeline = Timeline()
    let preview = ChatPreviewViewModel(room: room, repository: timeline)
    let task = Task { await preview.run() }

    timeline.publish.yield([message("a", .text("Hi"))])
    await waitUntil { await timeline.calls.contains(.loadOlder) }
    timeline.publish.yield([message("z", .text("Older")), message("a", .text("Hi"))])
    await waitUntil { preview.state.lines?.count == 2 }

    task.cancel()
    await task.value
    let calls = await timeline.calls
    #expect(calls.filter { $0 == .loadOlder }.count == 1)
    #expect(!calls.contains(.markAsRead))
    #expect(calls.last == .close)
  }

  @Test func showsAFailureWhenTheTimelineCannotOpen() async {
    let timeline = Timeline()
    await timeline.failOpening()
    let preview = ChatPreviewViewModel(room: room, repository: timeline)

    await preview.run()

    #expect(preview.state == .failed)
    let calls = await timeline.calls
    #expect(calls == [.open, .close])
  }

  @Test func spacesAndInvitationsHaveNoPreview() {
    let viewModel = ChatListViewModel(
      repository: FakeRoomListRepository(), previewTimeline: { _ in Timeline() }, logOut: { true })
    let space = RoomSummary(
      id: "!s", name: "Space", lastMessageText: nil, lastMessageSender: nil, lastActivity: nil,
      isSpace: true)
    let invite = RoomSummary(
      id: "!i", name: "Invite", lastMessageText: nil, lastMessageSender: nil, lastActivity: nil,
      isInvite: true)

    #expect(viewModel.makePreview(room) != nil)
    #expect(viewModel.makePreview(space) == nil)
    #expect(viewModel.makePreview(invite) == nil)
    #expect(
      ChatListViewModel(repository: FakeRoomListRepository(), logOut: { true }).makePreview(room)
        == nil)
  }
}

extension ChatPreviewViewModel.State {
  fileprivate var lines: [ChatPreviewViewModel.Line]? {
    if case .loaded(let lines) = self { lines } else { nil }
  }
}
