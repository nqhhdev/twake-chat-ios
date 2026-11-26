import Foundation
import Testing

@testable import Domain

struct ThreadActivityTests {
  private func candidate(rootIsOwn: Bool, latestIsOwn: Bool?, thread: String = "$t")
    -> ThreadActivityCandidate
  {
    ThreadActivityCandidate(
      roomId: "!r:a", threadId: thread, rootIsOwn: rootIsOwn, latestIsOwn: latestIsOwn)
  }

  private func entry(_ pref: ThreadPref, thread: String = "$t") -> ThreadPrefEntry {
    ThreadPrefEntry(roomId: "!r:a", threadId: thread, pref: pref)
  }

  @Test func aThreadTheUserStartedIsActiveWhenSomeoneElseReplied() {
    #expect(ThreadPrefs.isActive(candidate(rootIsOwn: true, latestIsOwn: false), entries: []))
  }

  @Test func aThreadWhoseLastReplyIsTheUsersOwnOrWithoutReplyIsNotActive() {
    #expect(!ThreadPrefs.isActive(candidate(rootIsOwn: true, latestIsOwn: true), entries: []))
    #expect(!ThreadPrefs.isActive(candidate(rootIsOwn: true, latestIsOwn: nil), entries: []))
  }

  @Test func anotherThreadIsActiveOnlyWhenFollowed() {
    let other = candidate(rootIsOwn: false, latestIsOwn: false)
    #expect(!ThreadPrefs.isActive(other, entries: []))
    #expect(ThreadPrefs.isActive(other, entries: [entry(.follow)]))
    #expect(!ThreadPrefs.isActive(other, entries: [entry(.follow, thread: "$other")]))
  }

  @Test func anUnfollowedOrMutedThreadIsNeverActive() {
    let own = candidate(rootIsOwn: true, latestIsOwn: false)
    #expect(!ThreadPrefs.isActive(own, entries: [entry(.unfollow)]))
    #expect(!ThreadPrefs.isActive(own, entries: [entry(.mute)]))
  }

  @Test func activeThreadsComeFirstNewestFirstWithoutDuplicates() {
    func thread(_ id: String, _ seconds: TimeInterval?) -> FollowedThread {
      FollowedThread(
        entry: entry(.follow, thread: id), roomName: "Team", rootSenderName: nil, rootText: nil,
        date: seconds.map { Date(timeIntervalSince1970: $0) })
    }
    let merged = FollowedThread.merged(
      followed: [thread("$f", nil), thread("$b", nil)],
      active: [thread("$a", 1), thread("$b", 3), thread("$c", 2)])
    #expect(merged.map(\.entry.threadId) == ["$b", "$c", "$a", "$f"])
  }

  @Test func followingSubscribesOnlyWhereTheServerAnnouncesThreadSubscriptions() {
    #expect(ThreadPrefs.usesSubscriptions(["org.matrix.msc4306"]))
    #expect(!ThreadPrefs.usesSubscriptions(["org.matrix.msc3440"]))
    #expect(ThreadPrefs.isSubscribed(.follow))
    #expect(!ThreadPrefs.isSubscribed(.unfollow))
    #expect(!ThreadPrefs.isSubscribed(.mute))
  }
}
