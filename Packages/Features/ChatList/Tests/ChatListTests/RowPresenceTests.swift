import ChatListTestSupport
import Domain
import Foundation
import Testing

@testable import ChatList

@MainActor
struct RowPresenceTests {
  private final class Lookups: @unchecked Sendable {
    var userIds: [String] = []
    var answer: Presence? = Presence(isOnline: true)
  }

  private static func direct(_ userId: String?, isDirect: Bool = true) -> RoomSummary {
    RoomSummary(
      id: "!dm:example.org", name: "Bob", lastMessageText: nil, lastMessageSender: nil,
      lastActivity: nil, isDirect: isDirect, directUserId: userId)
  }

  private func viewModel(_ lookups: Lookups) -> ChatListViewModel {
    ChatListViewModel(
      repository: FakeRoomListRepository(),
      presence: { userId in
        await MainActor.run { lookups.userIds.append(userId) }
        return await MainActor.run { lookups.answer }
      },
      logOut: { true })
  }

  @Test func aDirectChatShowsTheOtherPersonsPresence() async {
    let lookups = Lookups()
    let viewModel = viewModel(lookups)
    let room = Self.direct("@bob:example.org")
    #expect(viewModel.presenceDot(of: room) == nil)
    await viewModel.refreshPresence(of: room)
    #expect(viewModel.presenceDot(of: room) == .online)
    #expect(lookups.userIds == ["@bob:example.org"])
  }

  @Test func anAwayPersonGetsTheAwayDotAndAnOfflineOneNone() async {
    let lookups = Lookups()
    lookups.answer = Presence(isOnline: false, isAway: true)
    let viewModel = viewModel(lookups)
    let room = Self.direct("@bob:example.org")
    await viewModel.refreshPresence(of: room)
    #expect(viewModel.presenceDot(of: room) == .away)
    lookups.answer = Presence(isOnline: false)
    await viewModel.refreshPresence(of: room, now: .now + .seconds(61))
    #expect(viewModel.presenceDot(of: room) == nil)
  }

  @Test func theRowAsksAtMostOnceAMinuteAndNeverOnATimer() async {
    let lookups = Lookups()
    let viewModel = viewModel(lookups)
    let room = Self.direct("@bob:example.org")
    let start = ContinuousClock.now
    await viewModel.refreshPresence(of: room, now: start)
    await viewModel.refreshPresence(of: room, now: start + .seconds(30))
    #expect(lookups.userIds.count == 1)
    await viewModel.refreshPresence(of: room, now: start + .seconds(60))
    #expect(lookups.userIds.count == 2)
  }

  @Test func groupsAndUnknownPeopleAreNotAsked() async {
    let lookups = Lookups()
    let viewModel = viewModel(lookups)
    await viewModel.refreshPresence(of: Self.direct(nil))
    await viewModel.refreshPresence(of: Self.direct("@bob:example.org", isDirect: false))
    #expect(lookups.userIds.isEmpty)
    #expect(viewModel.presenceDot(of: Self.direct("@bob:example.org", isDirect: false)) == nil)
  }
}
