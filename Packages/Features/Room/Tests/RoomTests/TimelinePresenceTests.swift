import Domain
import Foundation
import RoomTestSupport
import Testing

@testable import Room

@MainActor
struct TimelinePresenceTests {
  private func viewModel(_ details: FakeRoomDetailsRepository?) -> RoomViewModel {
    RoomViewModel(
      roomId: "!r", roomName: "Team", repository: FakeTimelineRepository(),
      media: FakeMediaRepository(), details: details)
  }

  @Test func theAuthorsAvatarShowsTheSamePresenceAsTheProfile() async {
    let details = FakeRoomDetailsRepository()
    details.presence = Presence(isOnline: true)
    let room = viewModel(details)
    #expect(room.presenceDot(of: "@bob:example.org") == nil)
    await room.refreshPresence(of: "@bob:example.org")
    #expect(room.presenceDot(of: "@bob:example.org") == .online)
    details.presence = Presence(isOnline: false, isAway: true)
    let later = ContinuousClock.now.advanced(by: .seconds(61))
    await room.refreshPresence(of: "@bob:example.org", now: later)
    #expect(room.presenceDot(of: "@bob:example.org") == .away)
  }

  @Test func presenceIsAskedOncePerMinuteForEachAuthor() async {
    let details = FakeRoomDetailsRepository()
    let room = viewModel(details)
    let now = ContinuousClock.now
    await room.refreshPresence(of: "@bob:example.org", now: now)
    await room.refreshPresence(of: "@bob:example.org", now: now.advanced(by: .seconds(30)))
    await room.refreshPresence(of: "@eve:example.org", now: now.advanced(by: .seconds(30)))
    #expect(details.presenceCalls == ["@bob:example.org", "@eve:example.org"])
  }

  @Test func withoutDetailsNoPresenceIsAsked() async {
    let room = viewModel(nil)
    await room.refreshPresence(of: "@bob:example.org")
    #expect(room.presenceDot(of: "@bob:example.org") == nil)
  }
}
