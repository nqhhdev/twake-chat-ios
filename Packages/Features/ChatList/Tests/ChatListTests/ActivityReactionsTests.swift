import ChatListTestSupport
import Domain
import Foundation
import Testing

@testable import ChatList

/// A hand-written `ActivityReactionsRepository` (ADR 0010) that answers the reactions it was given and keeps the rooms
/// it was asked about.
private final class FakeActivityReactions: ActivityReactionsRepository, @unchecked Sendable {
  let answer: [ActivityReaction]
  private(set) var askedRooms: [String]?

  init(_ answer: [ActivityReaction]) { self.answer = answer }

  func reactions(inRooms roomIds: [String]) async -> [ActivityReaction] {
    askedRooms = roomIds
    return answer
  }
}

@MainActor
struct ActivityReactionsTests {
  private let reaction = ActivityReaction(
    roomId: "!team:x", roomName: "Team", eventId: "$1", key: "👍", senderId: "@a:x",
    senderName: "Alice", reactedAt: Date(timeIntervalSince1970: 1), messageText: "Lunch?")

  @Test func loadsTheReactionsOfTheRepository() async {
    let repository = FakeActivityReactions([reaction])
    let viewModel = ChatListViewModel(
      repository: FakeRoomListRepository(), activityReactions: repository, logOut: { true })
    #expect(viewModel.reactions.isEmpty)

    await viewModel.loadReactions()

    #expect(viewModel.reactions == [reaction])
    #expect(repository.askedRooms == [])
  }

  @Test func withoutARepositoryThereIsNothingToLoad() async {
    let viewModel = ChatListViewModel(repository: FakeRoomListRepository(), logOut: { true })
    await viewModel.loadReactions()
    #expect(viewModel.reactions.isEmpty)
  }

  @Test func theTitleSaysWhoReactedWithWhat() {
    #expect(ChatListViewModel.title(of: reaction) == "Alice reacted 👍 to your message")
  }
}
