import Testing

@testable import MatrixData

/// The composer writes a mention as a matrix.to link; the proxy lists the linked users as intentional mentions.
struct MentionContentTests {
  @Test func findsEachLinkedUserOnce() {
    let text =
      "Hi [Alice](https://matrix.to/#/@alice:example.org) and [Bob](https://matrix.to/#/@bob:example.org),"
      + " [Alice](https://matrix.to/#/@alice:example.org) again"
    #expect(TimelineProxy.mentionedUserIds(in: text) == ["@alice:example.org", "@bob:example.org"])
  }

  @Test func plainTextAndRoomLinksMentionNobody() {
    #expect(TimelineProxy.mentionedUserIds(in: "hello @alice").isEmpty)
    #expect(TimelineProxy.mentionedUserIds(in: "see https://matrix.to/#/!room:example.org").isEmpty)
  }
}
