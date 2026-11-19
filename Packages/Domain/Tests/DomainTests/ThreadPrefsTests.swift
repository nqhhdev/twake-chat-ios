import Foundation
import Testing

@testable import Domain

struct ThreadPrefsTests {
  @Test func readsTheWebAccountDataAndLeavesOutMalformedEntries() {
    let json = """
      {"threads": [
        {"roomId": "!a:x", "threadId": "$1", "pref": "follow"},
        {"roomId": "!a:x", "threadId": "$2", "pref": "mute"},
        {"roomId": "!b:x", "threadId": "$3", "pref": "unfollow"},
        {"roomId": "!b:x", "threadId": "$4", "pref": "snooze"},
        {"roomId": "!b:x", "pref": "follow"},
        "not an object"
      ]}
      """
    #expect(
      ThreadPrefs.entries(fromJSON: Data(json.utf8)) == [
        ThreadPrefEntry(roomId: "!a:x", threadId: "$1", pref: .follow),
        ThreadPrefEntry(roomId: "!a:x", threadId: "$2", pref: .mute),
        ThreadPrefEntry(roomId: "!b:x", threadId: "$3", pref: .unfollow),
      ])
    #expect(ThreadPrefs.entries(fromJSON: nil).isEmpty)
    #expect(ThreadPrefs.entries(fromJSON: Data("{}".utf8)).isEmpty)
  }

  @Test func writesTheWebFormat() throws {
    let entries = [ThreadPrefEntry(roomId: "!a:x", threadId: "$1", pref: .mute)]
    let data = try #require(ThreadPrefs.json(entries))
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let threads = try #require(object["threads"] as? [[String: String]])
    #expect(threads == [["roomId": "!a:x", "threadId": "$1", "pref": "mute"]])
    #expect(ThreadPrefs.entries(fromJSON: data) == entries)
  }

  @Test func aNewChoiceReplacesTheOldOneAndComesFirst() {
    let entries = [
      ThreadPrefEntry(roomId: "!a:x", threadId: "$1", pref: .follow),
      ThreadPrefEntry(roomId: "!a:x", threadId: "$2", pref: .follow),
      // The same thread id in another room is another thread.
      ThreadPrefEntry(roomId: "!b:x", threadId: "$2", pref: .follow),
    ]
    #expect(
      ThreadPrefs.with(entries, roomId: "!a:x", threadId: "$2", pref: .mute) == [
        ThreadPrefEntry(roomId: "!a:x", threadId: "$2", pref: .mute),
        ThreadPrefEntry(roomId: "!a:x", threadId: "$1", pref: .follow),
        ThreadPrefEntry(roomId: "!b:x", threadId: "$2", pref: .follow),
      ])
  }

  @Test func keepsAtMostFiveHundredChoices() {
    let entries = (0..<ThreadPrefs.maxEntries).map {
      ThreadPrefEntry(roomId: "!a:x", threadId: "$\($0)", pref: .follow)
    }
    let updated = ThreadPrefs.with(entries, roomId: "!a:x", threadId: "$new", pref: .follow)
    #expect(updated.count == ThreadPrefs.maxEntries)
    #expect(updated.first?.threadId == "$new")
    #expect(updated.last?.threadId == "$\(ThreadPrefs.maxEntries - 2)")
  }

  @Test func theChoiceBeatsTakingPartAndAMutedThreadIsStillFollowed() {
    #expect(
      ThreadPrefs.follow(isParticipating: true, pref: nil)
        == ThreadFollow(isFollowing: true, isMuted: false))
    #expect(
      ThreadPrefs.follow(isParticipating: false, pref: nil)
        == ThreadFollow(isFollowing: false, isMuted: false))
    #expect(
      ThreadPrefs.follow(isParticipating: true, pref: .unfollow)
        == ThreadFollow(isFollowing: false, isMuted: false))
    #expect(
      ThreadPrefs.follow(isParticipating: false, pref: .follow)
        == ThreadFollow(isFollowing: true, isMuted: false))
    #expect(
      ThreadPrefs.follow(isParticipating: false, pref: .mute)
        == ThreadFollow(isFollowing: true, isMuted: true))
  }

  @Test func theMuteRuleIdIsTheWebPrefixAndTheRoot() {
    #expect(ThreadPrefs.accountDataType == "app.twake.chat.thread_prefs")
    #expect(ThreadPrefs.muteRuleId(threadId: "$root:x") == "app.twake.chat.thread.$root:x")
  }
}
