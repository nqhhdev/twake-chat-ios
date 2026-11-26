import Domain
import Foundation
import RoomTestSupport
import Testing

@testable import Room

@MainActor
struct ScheduledMessageTests {
  private let noon = Date(timeIntervalSince1970: 1_800_000_000)

  private func viewModel(schedulingOn: Bool = true) async -> (RoomViewModel, FakeTimelineRepository)
  {
    let repository = FakeTimelineRepository()
    repository.schedulingOn = schedulingOn
    let room = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: repository, media: FakeMediaRepository())
    await room.loadScheduling()
    return (room, repository)
  }

  @Test func schedulingIsOfferedOnlyWhereTheServerAndRoomAllowIt() async {
    let (off, _) = await viewModel(schedulingOn: false)
    off.draft = "Hi"
    #expect(!off.canScheduleDraft)
    let (on, _) = await viewModel()
    #expect(!on.canScheduleDraft)
    on.draft = "Hi"
    #expect(on.canScheduleDraft)
    on.edit(
      TimelineMessage(
        eventId: "$e", senderId: "@me", senderName: "Me", isOwn: true, date: .now,
        body: .text("Old")))
    #expect(!on.canScheduleDraft)
  }

  @Test func aScheduledReplyLeavesTheComposerAndJoinsTheList() async {
    let (room, repository) = await viewModel()
    room.reply(
      to: TimelineMessage(
        eventId: "$q", senderId: "@bob", senderName: "Bob", isOwn: false, date: .now,
        body: .text("When?")))
    room.draft = " Tomorrow "
    #expect(await room.schedule(at: noon))
    #expect(repository.calls.contains(.schedule("Tomorrow", noon, "$q")))
    #expect(room.draft.isEmpty)
    #expect(room.composerMode == .new)
    #expect(room.scheduled.map(\.text) == ["Tomorrow"])
  }

  @Test func aRefusedScheduleKeepsTheDraftAndSaysWhy() async {
    let (room, repository) = await viewModel()
    repository.scheduleResult = .failure(.delayTooLong(maxDelay: 7 * 24 * 3600))
    room.draft = "Later"
    #expect(await room.schedule(at: noon) == false)
    #expect(room.draft == "Later")
    #expect(room.errorMessage == "The server cannot hold a message that long (at most 168 hours).")
  }

  @Test func aScheduledMessageCanBeCancelledSentNowOrEdited() async {
    let (room, repository) = await viewModel()
    repository.scheduledList = [
      ScheduledMessage(id: "a", text: "One", sendAt: noon),
      ScheduledMessage(id: "b", text: "Two", sendAt: noon),
      ScheduledMessage(id: "c", text: "Three", sendAt: noon),
    ]
    await room.loadScheduling()
    await room.cancelScheduled(room.scheduled[0])
    await room.sendScheduledNow(room.scheduled[0])
    await room.editScheduled(room.scheduled[0])
    #expect(room.scheduled.isEmpty)
    #expect(room.draft == "Three")
    #expect(
      repository.calls.filter {
        switch $0 {
        case .cancelScheduled, .sendScheduledNow: true
        default: false
        }
      } == [.cancelScheduled("a"), .sendScheduledNow("b"), .cancelScheduled("c")])
  }

  @Test func aMessageAlreadySentCannotBeCancelled() async {
    let (room, repository) = await viewModel()
    repository.scheduledList = [ScheduledMessage(id: "a", text: "One", sendAt: noon)]
    await room.loadScheduling()
    repository.updatesScheduled = false
    repository.scheduledList = []
    await room.cancelScheduled(ScheduledMessage(id: "a", text: "One", sendAt: noon))
    #expect(
      room.errorMessage == "Could not cancel the scheduled message. It may have been sent already.")
    #expect(room.scheduled.isEmpty)
  }

  @Test(arguments: [
    (ScheduleError.unsupported, "This server cannot schedule messages."),
    (.encryptedRoom, "Messages cannot be scheduled in an encrypted chat."),
    (.tooMany, "Too many messages are scheduled. Cancel one first."),
    (.delayTooLong(maxDelay: nil), "The server cannot hold a message that long."),
  ])
  func eachRefusalHasItsMessage(error: ScheduleError, message: String) {
    #expect(RoomViewModel.scheduleMessage(error) == message)
  }

  @Test func theSheetProposesTheNextFullHour() {
    var calendar = Calendar.current
    calendar.timeZone = .current
    let now = calendar.date(
      from: DateComponents(year: 2026, month: 11, day: 26, hour: 9, minute: 40))!
    let proposed = ScheduleSheet.defaultDate(now: now)
    #expect(calendar.component(.hour, from: proposed) == 10)
    #expect(calendar.component(.minute, from: proposed) == 0)
  }
}
