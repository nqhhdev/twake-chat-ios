import ChatListTestSupport
import Domain
import Foundation
import Testing

@testable import ChatList

/// A hand-written `ThreadPrefsRepository` (ADR 0010) that answers the followed threads it was given.
private struct FakeThreadPrefs: ThreadPrefsRepository {
  let followed: [FollowedThread]

  func threadPrefs() async -> [ThreadPrefEntry] { followed.map(\.entry) }
  func setThreadPref(_ pref: ThreadPref, roomId: String, threadId: String)
    async throws(TimelineError)
  {}
  func followedThreads() async -> [FollowedThread] { followed }
}

@MainActor
struct ActivityFollowedThreadsTests {
  private func thread(_ id: String, sender: String?, text: String?) -> FollowedThread {
    FollowedThread(
      entry: ThreadPrefEntry(roomId: "!team:example.org", threadId: id, pref: .follow),
      roomName: "Team", rootSenderName: sender, rootText: text, date: nil)
  }

  @Test func loadsTheFollowedThreadsInTheRepositoryOrder() async {
    let followed = [
      thread("$2", sender: "Alice", text: "Lunch?"), thread("$1", sender: nil, text: nil),
    ]
    let viewModel = ChatListViewModel(
      repository: FakeRoomListRepository(), threadPrefs: FakeThreadPrefs(followed: followed),
      logOut: { true })
    #expect(viewModel.followedThreads.isEmpty)

    await viewModel.loadFollowedThreads()

    #expect(viewModel.followedThreads == followed)
  }

  @Test func withoutThreadPrefsThereIsNothingToLoad() async {
    let viewModel = ChatListViewModel(repository: FakeRoomListRepository(), logOut: { true })
    await viewModel.loadFollowedThreads()
    #expect(viewModel.followedThreads.isEmpty)
  }

  @Test func thePreviewIsTheSenderAndTheRootOrAPlaceholder() {
    #expect(
      ChatListViewModel.preview(of: thread("$1", sender: "Alice", text: "Lunch?"))
        == "Alice: Lunch?")
    #expect(ChatListViewModel.preview(of: thread("$1", sender: nil, text: "Lunch?")) == "Lunch?")
    #expect(ChatListViewModel.preview(of: thread("$1", sender: "Alice", text: nil)) == "Thread")
    #expect(ChatListViewModel.preview(of: thread("$1", sender: "Alice", text: "")) == "Thread")
  }
}
