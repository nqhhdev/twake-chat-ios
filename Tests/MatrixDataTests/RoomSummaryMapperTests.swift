import Domain
import Foundation
import Testing

@testable import MatrixData

/// The room summary mapper with `LatestEventValue` fixtures. The SDK values are written as implicit enum members of the
/// mapper's parameter types, so this file does not import the SDK (ADR 0006, scripts/check-architecture.sh rule 1).
/// Only enum cases can be built here: the SDK's struct initializers (`MsgLikeContent`, `MessageContent`) live in the
/// SDK binary, which this bundle does not link, so the message-text path is covered by `RoomListIntegrationTests`.
struct RoomSummaryMapperTests {
  private let id = "!room:example.org"
  /// 2023-11-14T22:13:20.123Z in milliseconds, as the SDK's `Timestamp`.
  private let millis: UInt64 = 1_700_000_000_123
  private var date: Date { Date(timeIntervalSince1970: 1_700_000_000.123) }

  @Test func noLatestEvent() {
    let summary = RoomSummaryMapper.summary(id: id, displayName: "Team", latestEvent: .none)
    #expect(
      summary
        == RoomSummary(
          id: id, name: "Team", lastMessageText: nil, lastMessageSender: nil, lastActivity: nil))
  }

  @Test func theNameFallsBackToTheRoomId() {
    #expect(RoomSummaryMapper.summary(id: id, displayName: nil, latestEvent: .none).name == id)
    #expect(RoomSummaryMapper.summary(id: id, displayName: "", latestEvent: .none).name == id)
  }

  @Test func aRemoteEventFromAKnownProfile() {
    let summary = RoomSummaryMapper.summary(
      id: id, displayName: "Team",
      latestEvent: .remote(
        timestamp: millis, sender: "@bob:example.org", isOwn: false,
        profile: .ready(displayName: "Bob", displayNameAmbiguous: false, avatarUrl: nil),
        content: .callInvite))
    #expect(
      summary
        == RoomSummary(
          id: id, name: "Team", lastMessageText: nil, lastMessageSender: "Bob", lastActivity: date))
  }

  @Test(arguments: [false, true])
  func theSenderIdWhenTheProfileHasNoName(ready: Bool) {
    let summary = RoomSummaryMapper.summary(
      id: id, displayName: "Team",
      latestEvent: .local(
        timestamp: millis, sender: "@me:example.org",
        profile: ready
          ? .ready(displayName: nil, displayNameAmbiguous: false, avatarUrl: nil) : .unavailable,
        content: .rtcNotification, state: .isSending))
    #expect(summary.lastMessageSender == "@me:example.org")
    #expect(summary.lastActivity == date)
  }

  @Test func nonMessageContentHasNoText() {
    let summary = RoomSummaryMapper.summary(
      id: id, displayName: "Team",
      latestEvent: .remote(
        timestamp: millis, sender: "@bob:example.org", isOwn: false, profile: .pending,
        content: .profileChange(
          displayName: "Bob", prevDisplayName: nil, avatarUrl: nil, prevAvatarUrl: nil)))
    #expect(summary.lastMessageText == nil)
    #expect(summary.lastMessageSender == "@bob:example.org")
  }

  // MARK: Tester (TWAK-66). The message-text path cannot be built here: the SDK struct initializers are dead-stripped
  // from the MatrixData product this bundle links (tried: undefined symbols), so `RoomListIntegrationTests` covers it.

  /// A loaded profile with an empty display name falls back to the sender id, as a missing one does.
  @Test func anEmptyProfileNameFallsBackToTheSenderId() {
    let summary = RoomSummaryMapper.summary(
      id: id, displayName: "Team",
      latestEvent: .remote(
        timestamp: millis, sender: "@bob:example.org", isOwn: false,
        profile: .ready(displayName: "", displayNameAmbiguous: false, avatarUrl: nil),
        content: .callInvite))
    #expect(summary.lastMessageSender == "@bob:example.org")
  }

  @Test func anInviteHasADateButNoMessage() {
    let summary = RoomSummaryMapper.summary(
      id: id, displayName: "Team",
      latestEvent: .remoteInvite(timestamp: millis, inviter: "@bob:example.org", inviterProfile: .pending))
    #expect(summary.lastMessageText == nil)
    #expect(summary.lastMessageSender == nil)
    #expect(summary.lastActivity == date)
  }
}
