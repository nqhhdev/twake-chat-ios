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
    RoomViewModel(
      roomId: "!room:example.org", roomName: "Team", repository: repository,
      media: FakeMediaRepository())
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
    #expect(repository.calls == [.typing(false), .send("hi there")])
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
    #expect(repository.calls == [.typing(false), .reply("sure", "$1")])
    #expect(viewModel.composerMode == .new)
  }

  @Test func editingPutsTheTextInTheComposerAndSendsAnEdit() async {
    let repository = FakeTimelineRepository()
    let viewModel = viewModel(repository)
    viewModel.edit(message("$1", own: true, text: "typo"))
    #expect(viewModel.draft == "typo")
    viewModel.draft = "fixed"
    await viewModel.send()
    #expect(repository.calls == [.typing(false), .edit("$1", "fixed")])
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

  @Test func theSavedDraftComesBackAndTheComposerIsSavedWhenTheScreenGoes() async {
    let repository = FakeTimelineRepository()
    repository.draft = "half a thought"
    let viewModel = viewModel(repository)
    let task = Task { await viewModel.start() }
    while !repository.calls.contains(.markAsRead) { await Task.yield() }
    #expect(viewModel.draft == "half a thought")
    viewModel.draft = "a whole thought"
    repository.finish()
    await task.value
    #expect(repository.draft == "a whole thought")
  }

  @Test func anEditInProgressIsNotSavedAsTheDraft() async {
    let repository = FakeTimelineRepository()
    let viewModel = viewModel(repository)
    let task = Task { await viewModel.start() }
    while !repository.calls.contains(.markAsRead) { await Task.yield() }
    viewModel.edit(message("$1", own: true, text: "typo"))
    repository.finish()
    await task.value
    #expect(repository.draft == nil)
  }

  @Test func typingAtSuggestsMembersAndPickingWritesTheMention() async {
    let details = FakeRoomDetailsRepository()
    details.members = [
      .init(id: "@alice:example.org", displayName: "Alice Martin", membership: .joined),
      .init(id: "@bob:example.org", displayName: "Bob", membership: .joined),
    ]
    let viewModel = RoomViewModel(
      roomId: "!room:example.org", roomName: "Team", repository: FakeTimelineRepository(),
      media: FakeMediaRepository(), details: details)
    viewModel.draft = "Hi @ali"
    #expect(viewModel.mentionQuery == "ali")
    await viewModel.loadMembersIfNeeded()
    #expect(viewModel.mentionSuggestions.map(\.id) == ["@alice:example.org"])
    viewModel.pickMention(viewModel.mentionSuggestions[0])
    #expect(viewModel.draft == "Hi @Alice Martin ")
    #expect(viewModel.mentionQuery == nil || viewModel.mentionSuggestions.isEmpty)
  }

  @Test func anAtInsideAWordIsNotAMention() {
    let viewModel = viewModel(FakeTimelineRepository())
    viewModel.draft = "mail me at bob@example.org"
    #expect(viewModel.mentionQuery == nil)
  }

  @Test func sendingTurnsPickedMentionsIntoLinks() async {
    let repository = FakeTimelineRepository()
    let viewModel = viewModel(repository)
    viewModel.draft = "Hi @"
    viewModel.pickMention(
      .init(id: "@alice:example.org", displayName: "Alice", membership: .joined))
    viewModel.draft += "how are you?"
    await viewModel.send()
    #expect(
      repository.calls.contains(
        .send("Hi [Alice](https://matrix.to/#/@alice:example.org) how are you?")))
    #expect(viewModel.mentions.isEmpty)
  }

  @Test func reportingAndBlockingAskTheRepository() async {
    let repository = FakeTimelineRepository()
    let viewModel = viewModel(repository)
    let message = message("$9", text: "spam")
    await viewModel.report(message, reason: "  spam  ")
    await viewModel.block(message)
    #expect(repository.calls.contains(.report("$9", "spam")))
    #expect(repository.calls.contains(.ignore(message.senderId)))
  }

  @Test func loadingWhileVisibleKeepsPagingUntilTheStart() async {
    let repository = FakeTimelineRepository()
    let viewModel = viewModel(repository)
    let task = Task { await viewModel.loadOlderWhileVisible() }
    while repository.calls.filter({ $0 == .loadOlder }).count < 2 { await Task.yield() }
    repository.reachesStart = true
    await task.value
    #expect(viewModel.reachedStart)
  }

  @Test func jumpingToALoadedMessageScrollsAndFlashesIt() async {
    let repository = FakeTimelineRepository()
    let viewModel = viewModel(repository)
    let task = Task { await viewModel.start() }
    while !repository.calls.contains(.markAsRead) { await Task.yield() }
    let item = TimelineItem(id: "row1", kind: .message(message("$1")))
    repository.publish([item])
    while viewModel.state != .loaded([item]) { await Task.yield() }
    await viewModel.jump(toEvent: "$1")
    #expect(viewModel.scrollTarget == "row1")
    #expect(viewModel.highlightedEventId == "$1")
    repository.finish()
    await task.value
  }

  @Test func jumpingToAnOlderMessageLoadsPagesUntilItShows() async {
    let repository = FakeTimelineRepository()
    let viewModel = viewModel(repository)
    let task = Task { await viewModel.start() }
    while !repository.calls.contains(.markAsRead) { await Task.yield() }
    let newer = TimelineItem(id: "row2", kind: .message(message("$2")))
    repository.publish([newer])
    while viewModel.state != .loaded([newer]) { await Task.yield() }
    while !repository.calls.contains(.loadOlder) || viewModel.isLoadingOlder { await Task.yield() }
    let pagesBefore = repository.calls.filter { $0 == .loadOlder }.count
    let jump = Task { await viewModel.jump(toEvent: "$1") }
    // The older page arrives through the timeline once the jump asked for it.
    while repository.calls.filter({ $0 == .loadOlder }).count == pagesBefore { await Task.yield() }
    repository.publish([TimelineItem(id: "row1", kind: .message(message("$1"))), newer])
    await jump.value
    #expect(viewModel.scrollTarget == "row1")
    #expect(viewModel.highlightedEventId == "$1")
    repository.finish()
    await task.value
  }

  @Test func jumpingToAMessageBeforeTheStartSaysItIsNotFound() async {
    let repository = FakeTimelineRepository()
    repository.reachesStart = true
    let viewModel = viewModel(repository)
    let task = Task { await viewModel.start() }
    while !repository.calls.contains(.markAsRead) { await Task.yield() }
    await viewModel.jump(toEvent: "$missing")
    #expect(viewModel.scrollTarget == nil)
    #expect(viewModel.toast == "Could not find that message")
    repository.finish()
    await task.value
  }

  @Test func retryingAskstheRepositoryToSendAgain() async {
    let repository = FakeTimelineRepository()
    let viewModel = viewModel(repository)
    await viewModel.retryFailedSends()
    #expect(repository.calls.contains(.retry))
  }

  @Test func reactorsAndReadersOpenThePeopleSheet() {
    let viewModel = viewModel(FakeTimelineRepository())
    viewModel.showReactors(
      .init(key: "👍", count: 2, includesOwn: false, senderIds: ["@a:x", "@b:x"]))
    #expect(viewModel.peopleSheet?.userIds == ["@a:x", "@b:x"])
    let seen = TimelineMessage(
      eventId: "$1", senderId: "@me", senderName: "Me", isOwn: true, date: .now,
      body: .text("hi"), readCount: 1, readerIds: ["@bob:x"])
    viewModel.showReaders(of: seen)
    #expect(viewModel.peopleSheet?.title == "Seen by")
    #expect(viewModel.peopleSheet?.userIds == ["@bob:x"])
  }
}

@MainActor
struct RoomMediaTests {
  private let reference = MediaReference(source: "{}", mimeType: "application/pdf", size: 1_200_000)

  private func message(_ body: TimelineMessage.Body) -> TimelineMessage {
    TimelineMessage(
      eventId: "$1", senderId: "@bob:example.org", senderName: "Bob", isOwn: false, date: .now,
      body: body,
      media: reference)
  }

  @Test func aFileIsSavedUnderItsName() async {
    let media = FakeMediaRepository()
    let viewModel = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: FakeTimelineRepository(), media: media)
    let url = await viewModel.file(of: message(.file(name: "report.pdf")))
    #expect(url?.lastPathComponent == "report.pdf")
    #expect(media.fileNames == ["report.pdf"])
  }

  @Test func aFailedDownloadShowsAnError() async {
    let media = FakeMediaRepository()
    media.result = .failure(.downloadFailed)
    let viewModel = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: FakeTimelineRepository(), media: media)
    #expect(await viewModel.file(of: message(.file(name: "report.pdf"))) == nil)
    #expect(viewModel.errorMessage == "Could not download the file.")
  }

  @Test func emptyCaptionsAreNotShown() {
    #expect(MessageRow.caption(of: .image(caption: "")) == nil)
    #expect(MessageRow.caption(of: .image(caption: "Holiday")) == "Holiday")
    #expect(MessageRow.caption(of: .file(name: "a.pdf")) == nil)
  }

  @Test func aPictureKeepsItsAspectRatio() {
    #expect(MediaReference(source: "{}", width: 200, height: 100).aspectRatio == 0.5)
    #expect(MediaReference(source: "{}").aspectRatio == nil)
  }

  @Test func sizesReadLikeFiles() {
    #expect(RoomViewModel.sizeText(nil) == nil)
    #expect(RoomViewModel.sizeText(1_200_000) != nil)
  }
}

@MainActor
struct RoomSendFeedbackTests {
  @Test func eachSendBumpsTheSendCountForTheButtonAnimation() async {
    let viewModel = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: FakeTimelineRepository(),
      media: FakeMediaRepository())
    viewModel.draft = "one"
    await viewModel.send()
    viewModel.draft = "two"
    await viewModel.send()
    #expect(viewModel.sendCount == 2)
  }
}

@MainActor
struct RoomAttachmentAndTypingTests {
  private func viewModel(_ repository: FakeTimelineRepository) -> RoomViewModel {
    RoomViewModel(
      roomId: "!r", roomName: "Team", repository: repository, media: FakeMediaRepository())
  }

  @Test func anAttachmentIsSentAsAReplyWhenReplying() async {
    let repository = FakeTimelineRepository()
    let viewModel = viewModel(repository)
    viewModel.reply(
      to: TimelineMessage(
        eventId: "$1", senderId: "@b", senderName: "Bob", isOwn: false, date: .now,
        body: .text("look")))
    let url = URL(filePath: "/tmp/a.jpg")
    await viewModel.send(
      attachment: .image(width: 10, height: 20), fileURL: url, mimeType: "image/jpeg", size: 3)
    #expect(
      repository.calls == [
        .attachment(
          OutgoingAttachment(
            kind: .image(width: 10, height: 20), fileURL: url, mimeType: "image/jpeg", size: 3,
            replyTo: "$1"))
      ])
    #expect(viewModel.composerMode == .new)
    #expect(viewModel.uploadCount == 0)
  }

  @Test func aFailedUploadShowsAnError() async {
    let repository = FakeTimelineRepository()
    repository.actionResult = .failure(.requestFailed)
    let viewModel = viewModel(repository)
    await viewModel.send(
      attachment: .file, fileURL: URL(filePath: "/tmp/a.pdf"), mimeType: nil, size: nil)
    #expect(viewModel.errorMessage == "Could not send the attachment. Please try again.")
  }

  @Test func typingIsSentWhenTheDraftStartsAndStops() async {
    let repository = FakeTimelineRepository()
    let viewModel = viewModel(repository)
    await viewModel.draftDidChange(from: "", to: "h")
    await viewModel.draftDidChange(from: "h", to: "he")
    await viewModel.draftDidChange(from: "he", to: "")
    #expect(repository.calls == [.typing(true), .typing(false)])
  }

  @Test(.timeLimit(.minutes(1))) func theTypingTextNamesWhoIsTyping() async {
    let repository = FakeTimelineRepository()
    let viewModel = viewModel(repository)
    #expect(viewModel.typingText == nil)
    let task = Task { await viewModel.start() }
    // The room subscribes to typing in its own task; names published before that would be lost.
    while !repository.isFollowingTyping { await Task.yield() }
    repository.publishTyping(["Alice"])
    while viewModel.typingNames != ["Alice"] { await Task.yield() }
    #expect(viewModel.typingText == "Alice is typing…")
    repository.publishTyping(["Alice", "Bob", "Carol"])
    while viewModel.typingNames.count != 3 { await Task.yield() }
    #expect(viewModel.typingText == "Alice and 2 others are typing…")
    repository.finish()
    await task.value
  }
}

@MainActor
struct RoomPinAndForwardTests {
  private func message(_ id: String, _ text: String = "hi") -> TimelineMessage {
    TimelineMessage(
      eventId: id, senderId: "@b", senderName: "Bob", isOwn: false, date: .now, body: .text(text))
  }

  @Test func pinningReloadsThePinsAndShowsTheLatest() async {
    let repository = FakeTimelineRepository()
    let viewModel = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: repository, media: FakeMediaRepository())
    repository.pinned = [message("$1", "first"), message("$2", "second")]
    await viewModel.togglePin(message("$3"))
    #expect(repository.calls == [.pin(true, "$3")])
    #expect(viewModel.currentPinned?.eventId == "$2")
    #expect(viewModel.isPinned(message("$1")))
    #expect(viewModel.toast == "Pinned")
  }

  @Test func theBannerCyclesBackwardsThroughThePins() async {
    let repository = FakeTimelineRepository()
    repository.pinned = [message("$1"), message("$2"), message("$3")]
    let viewModel = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: repository, media: FakeMediaRepository())
    await viewModel.loadPinned()
    #expect(viewModel.pinnedIndex == 2)
    viewModel.showPreviousPinned()
    viewModel.showPreviousPinned()
    viewModel.showPreviousPinned()
    #expect(viewModel.pinnedIndex == 2)
  }

  @Test func unpinningAPinnedMessage() async {
    let repository = FakeTimelineRepository()
    repository.pinned = [message("$1")]
    let viewModel = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: repository, media: FakeMediaRepository())
    await viewModel.loadPinned()
    await viewModel.togglePin(message("$1"))
    #expect(repository.calls == [.pin(false, "$1")])
  }

  @Test func forwardingSendsToTheChosenRoom() async {
    let repository = FakeTimelineRepository()
    let viewModel = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: repository, media: FakeMediaRepository())
    let target = RoomSummary(
      id: "!other", name: "Other", lastMessageText: nil, lastMessageSender: nil, lastActivity: nil)
    await viewModel.forward(message("$1"), to: target)
    #expect(repository.calls == [.forward("$1", "!other")])
    #expect(viewModel.toast == "Forwarded to Other")
  }

  @Test func aFailedForwardShowsAnError() async {
    let repository = FakeTimelineRepository()
    repository.actionResult = .failure(.requestFailed)
    let viewModel = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: repository, media: FakeMediaRepository())
    let target = RoomSummary(
      id: "!o", name: "O", lastMessageText: nil, lastMessageSender: nil, lastActivity: nil)
    await viewModel.forward(message("$1"), to: target)
    #expect(viewModel.errorMessage == "Could not forward the message.")
  }
}

@MainActor
struct VoiceMessageTests {
  @Test func theWaveformKeepsTheLoudestSampleOfEachSlice() {
    let samples: [Float] = [0.1, 0.9, 0.2, 0.3, 0.8, 0.1]
    #expect(VoiceRecorder.downsample(samples, to: 3) == [0.9, 0.3, 0.8])
    #expect(VoiceRecorder.downsample([0.5], to: 3) == [0.5])
  }

  @Test func durationsReadAsMinutesAndSeconds() {
    #expect(AudioMessageRow.time(0) == "0:00")
    #expect(AudioMessageRow.time(65.4) == "1:05")
    #expect(AudioMessageRow.time(-3) == "0:00")
  }

  @Test func aVoiceMessageIsSentAsVoice() async {
    let repository = FakeTimelineRepository()
    let viewModel = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: repository, media: FakeMediaRepository())
    let url = URL(filePath: "/tmp/voice.m4a")
    await viewModel.send(
      attachment: .voice(duration: 3, waveform: [0.2, 0.8]), fileURL: url, mimeType: "audio/mp4",
      size: nil)
    #expect(
      repository.calls == [
        .attachment(
          OutgoingAttachment(
            kind: .voice(duration: 3, waveform: [0.2, 0.8]), fileURL: url, mimeType: "audio/mp4",
            size: nil))
      ])
  }
}

/// A chat the user left opens read-only; Rejoin brings the composer back.
@MainActor
struct ArchivedRoomTests {
  @Test func rejoiningAnArchivedChatShowsTheComposerAgain() async {
    var calls = 0
    let viewModel = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: FakeTimelineRepository(),
      media: FakeMediaRepository(), isArchived: true,
      rejoin: {
        calls += 1
        return true
      })
    #expect(viewModel.isArchived)
    await viewModel.rejoin()
    #expect(calls == 1)
    #expect(viewModel.isArchived == false)
  }

  @Test func aFailedRejoinStaysReadOnlyAndSaysWhy() async {
    let viewModel = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: FakeTimelineRepository(),
      media: FakeMediaRepository(), isArchived: true, rejoin: { false })
    await viewModel.rejoin()
    #expect(viewModel.isArchived)
    #expect(
      viewModel.errorMessage == "Could not join this chat again. It may need an invitation.")
  }
}

/// The preview before sending: one caption for the batch, with the last item; the draft moves into it.
@MainActor
struct SendBatchTests {
  private func file(_ name: String) throws -> AttachmentLoader.Loaded {
    let folder = FileManager.default.temporaryDirectory.appending(path: "batch-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appending(path: name)
    try Data([1]).write(to: url)
    return AttachmentLoader.Loaded(
      kind: .image(width: 1, height: 1), fileURL: url, mimeType: "image/png", size: 1)
  }

  @Test func theCaptionGoesWithTheLastItemAndTheCopiesAreDeleted() async throws {
    let repository = FakeTimelineRepository()
    let viewModel = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: repository, media: FakeMediaRepository())
    viewModel.draft = "Holiday"
    let first = try file("a.png")
    let second = try file("b.png")
    await viewModel.send(batch: [first, second], caption: " Holiday ")
    let sent = repository.calls.compactMap { call -> OutgoingAttachment? in
      if case .attachment(let attachment) = call { attachment } else { nil }
    }
    #expect(sent.map(\.fileURL.lastPathComponent) == ["a.png", "b.png"])
    #expect(sent.map(\.caption) == [nil, "Holiday"])
    #expect(viewModel.draft.isEmpty)
    let path = first.fileURL.path(percentEncoded: false)
    #expect(FileManager.default.fileExists(atPath: path) == false)
  }

  @Test func anEmptyCaptionSendsNone() async throws {
    let repository = FakeTimelineRepository()
    let viewModel = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: repository, media: FakeMediaRepository())
    await viewModel.send(batch: [try file("a.png")], caption: "   ")
    let sent = repository.calls.compactMap { call -> OutgoingAttachment? in
      if case .attachment(let attachment) = call { attachment } else { nil }
    }
    #expect(sent.map(\.caption) == [nil])
  }
}

/// Which link of a text message gets a preview card.
@MainActor
struct PreviewLinkTests {
  @Test func theFirstWebLinkGetsACard() {
    #expect(
      RoomViewModel.previewLink(in: "see https://twake.app and https://linagora.com")?
        .absoluteString == "https://twake.app")
  }

  @Test func aMatrixLinkOrATextWithoutLinkGetsNone() {
    #expect(RoomViewModel.previewLink(in: "https://matrix.to/#/@alice:example.org") == nil)
    #expect(RoomViewModel.previewLink(in: "no link here") == nil)
  }
}

/// The banner that warns encrypted messages may not show on this device.
@MainActor
struct SessionWarningBannerTests {
  /// What the app answers, changed between checks.
  private final class Answer: @unchecked Sendable {
    var warning: SessionWarning?
  }

  @Test func theBannerFollowsWhatTheAppAnswers() async {
    let answer = Answer()
    answer.warning = .unverified
    let viewModel = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: FakeTimelineRepository(),
      media: FakeMediaRepository(), checkSession: { answer.warning })
    #expect(viewModel.sessionWarning == nil)
    await viewModel.refreshSessionWarning()
    #expect(viewModel.sessionWarning == .unverified)
    answer.warning = .recoveryIncomplete
    await viewModel.refreshSessionWarning()
    #expect(viewModel.sessionWarning == .recoveryIncomplete)
    answer.warning = nil
    await viewModel.refreshSessionWarning()
    #expect(viewModel.sessionWarning == nil)
  }

  @Test func withoutACheckThereIsNoBanner() async {
    let viewModel = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: FakeTimelineRepository(),
      media: FakeMediaRepository())
    await viewModel.refreshSessionWarning()
    #expect(viewModel.sessionWarning == nil)
  }
}

/// The chat settings decide which room events the rows show.
@MainActor
struct ChatDisplayRowsTests {
  /// What Settings holds, changed between reads.
  private final class Choice {
    var settings = ChatDisplaySettings()
  }

  @Test func hiddenRoomEventsLeaveTheRowsAndComeBackWhenShown() async {
    let repository = FakeTimelineRepository()
    let choice = Choice()
    let viewModel = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: repository, media: FakeMediaRepository(),
      display: { choice.settings })
    let task = Task { await viewModel.start() }
    while !repository.calls.contains(.markAsRead) { await Task.yield() }
    repository.publish([
      TimelineItem(id: "joined", kind: .stateNotice("Bob joined")),
      TimelineItem(
        id: "topic", kind: .stateNotice("Bob changed the topic"), visibility: .unimportant),
      TimelineItem(id: "custom", kind: .stateNotice("Unknown event 'x'"), visibility: .unknown),
    ])
    while viewModel.rows.isEmpty { await Task.yield() }
    #expect(viewModel.rows.map(\.id) == ["joined"])
    choice.settings.hidesUnimportantEvents = false
    #expect(viewModel.rows.map(\.id) == ["joined", "topic"])
    task.cancel()
  }
}
