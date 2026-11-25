import Foundation
import Testing

@testable import MatrixData

/// The Activity lists the reactions of other people on the user's sent messages (web D58), read from the timeline items
/// the SDK holds.
struct ActivityReactionsProxyTests {
  /// What the proxy finds on one message, of the user or not, with a 👍 from Alice and one from the user. The SDK types
  /// are built through the proxy's signature: only MatrixData imports the SDK (ADR 0006).
  private func found(isOwn: Bool, sent: Bool = true) -> [ActivityReactionsProxy.Found] {
    ActivityReactionsProxy.ownReactions(
      on: .init(
        isRemote: true,
        eventOrTransactionId: sent
          ? .eventId(eventId: "$msg") : .transactionId(transactionId: "t1"),
        sender: isOwn ? "@me:x" : "@a:x", senderProfile: .unavailable, forwarder: nil,
        forwarderProfile: nil, isOwn: isOwn, isEditable: isOwn,
        content: .msgLike(
          content: .init(
            kind: .redacted,
            reactions: [
              .init(
                key: "👍",
                senders: [
                  .init(senderId: "@a:x", timestamp: 2_000),
                  .init(senderId: "@me:x", timestamp: 3_000),
                ])
            ], inReplyTo: nil, threadRoot: nil, threadSummary: nil)),
        timestamp: 0, localSendState: nil, localCreatedAt: nil, readReceipts: [:], origin: nil,
        canBeRepliedTo: true, lazyProvider: .init(noHandle: .init())),
      ownUserId: "@me:x")
  }

  @Test func listsOtherPeoplesReactionsOnTheUsersMessage() {
    #expect(
      found(isOwn: true) == [
        .init(
          eventId: "$msg", key: "👍", senderId: "@a:x",
          reactedAt: Date(timeIntervalSince1970: 2), messageText: "This message has been deleted")
      ])
  }

  @Test func ignoresReactionsOnSomeoneElsesMessage() {
    #expect(found(isOwn: false).isEmpty)
  }

  @Test func ignoresAMessageNotSentYet() {
    #expect(found(isOwn: true, sent: false).isEmpty)
  }

  @Test func readsTheLiveTimelineWithThreadsAndWithoutReceipts() {
    let configuration = ActivityReactionsProxy.configuration
    #expect(configuration.focus == .live(hideThreadedEvents: false))
    #expect(configuration.trackReadReceipts == .disabled)
  }
}
