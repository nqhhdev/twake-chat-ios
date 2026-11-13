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
