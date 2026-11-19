import Domain
import Foundation
import RoomTestSupport
import Testing

@testable import Room

/// A hand-written `ThreadPrefsRepository` (ADR 0010): keeps the choices in memory and records each write.
private final class FakeThreadPrefs: ThreadPrefsRepository, @unchecked Sendable {
  private let lock = NSLock()
  private var _entries: [ThreadPrefEntry]
  private var _writes: [ThreadPrefEntry] = []
  var fails = false

  init(_ entries: [ThreadPrefEntry] = []) { _entries = entries }

  var writes: [ThreadPrefEntry] { lock.withLock { _writes } }

  func threadPrefs() async -> [ThreadPrefEntry] { lock.withLock { _entries } }

  func setThreadPref(_ pref: ThreadPref, roomId: String, threadId: String)
    async throws(TimelineError)
  {
    if fails { throw .requestFailed }
    lock.withLock {
      _writes.append(ThreadPrefEntry(roomId: roomId, threadId: threadId, pref: pref))
      _entries = ThreadPrefs.with(_entries, roomId: roomId, threadId: threadId, pref: pref)
    }
  }

  func followedThreads() async -> [FollowedThread] { [] }
}

@MainActor
struct ThreadFollowTests {
  private let room = "!room:example.org"

  private func thread(_ prefs: FakeThreadPrefs?, repository: FakeTimelineRepository = .init())
    -> RoomViewModel
  {
    RoomViewModel(
      roomId: room, roomName: "Team", repository: repository, media: FakeMediaRepository(),
      threadRootId: "$root", threadPrefs: prefs)
  }

  private func message(_ id: String, own: Bool) -> TimelineItem {
    TimelineItem(
      id: id,
      kind: .message(
        TimelineMessage(
          eventId: id, senderId: own ? "@me:example.org" : "@bob:example.org",
          senderName: own ? "Me" : "Bob", isOwn: own,
          date: Date(timeIntervalSince1970: 1_700_000_000), body: .text("hi"))))
  }

  @Test func onlyAThreadScreenWithThreadPrefsOffersTheMenu() {
    #expect(thread(FakeThreadPrefs()).canFollowThread)
    #expect(!thread(nil).canFollowThread)
    let main = RoomViewModel(
      roomId: room, roomName: "Team", repository: FakeTimelineRepository(),
      media: FakeMediaRepository(), threadPrefs: FakeThreadPrefs())
    #expect(!main.canFollowThread)
  }

  @Test func theThreadOfAnotherRoomOrRootIsNotThisOne() async {
    let prefs = FakeThreadPrefs([
      ThreadPrefEntry(roomId: "!other:example.org", threadId: "$root", pref: .mute),
      ThreadPrefEntry(roomId: room, threadId: "$other", pref: .unfollow),
      ThreadPrefEntry(roomId: room, threadId: "$root", pref: .follow),
    ])
    let viewModel = thread(prefs)
    await viewModel.loadThreadPref()
    #expect(viewModel.threadPref == .follow)
    #expect(viewModel.threadFollow == ThreadFollow(isFollowing: true, isMuted: false))
  }

  @Test func withoutAChoiceTakingPartFollowsTheThread() async {
    let repository = FakeTimelineRepository()
    let viewModel = thread(FakeThreadPrefs(), repository: repository)
    #expect(!viewModel.threadFollow.isFollowing)
    let task = Task { await viewModel.start() }
    while !repository.calls.contains(.markAsRead) { await Task.yield() }
    let items = [message("$root", own: false), message("$reply", own: true)]
    repository.publish(items)
    while viewModel.state != .loaded(items) { await Task.yield() }
    #expect(viewModel.threadFollow == ThreadFollow(isFollowing: true, isMuted: false))
    repository.finish()
    await task.value
  }

  @Test func unfollowBeatsTakingPartAndMuteStillFollows() async {
    let prefs = FakeThreadPrefs()
    let viewModel = thread(prefs)

    await viewModel.setThreadPref(.unfollow)
    #expect(viewModel.threadFollow == ThreadFollow(isFollowing: false, isMuted: false))
    #expect(viewModel.toast == "You no longer follow this thread")

    await viewModel.setThreadPref(.mute)
    #expect(viewModel.threadFollow == ThreadFollow(isFollowing: true, isMuted: true))
    #expect(
      prefs.writes == [
        ThreadPrefEntry(roomId: room, threadId: "$root", pref: .unfollow),
        ThreadPrefEntry(roomId: room, threadId: "$root", pref: .mute),
      ])
  }

  @Test func aFailedWriteKeepsTheChoiceAndSaysSo() async {
    let prefs = FakeThreadPrefs([ThreadPrefEntry(roomId: room, threadId: "$root", pref: .follow)])
    prefs.fails = true
    let viewModel = thread(prefs)
    await viewModel.loadThreadPref()

    await viewModel.setThreadPref(.mute)

    #expect(viewModel.threadPref == .follow)
    #expect(viewModel.errorMessage == "Could not update this thread.")
  }

  @Test func aThreadOpenedFromTheRoomKeepsTheThreadPrefs() {
    let main = RoomViewModel(
      roomId: room, roomName: "Team", repository: FakeTimelineRepository(),
      media: FakeMediaRepository(), threadTimeline: { _ in FakeTimelineRepository() },
      threadPrefs: FakeThreadPrefs())
    main.openThread(root: "$root")
    #expect(main.openedThread?.canFollowThread == true)
  }
}
