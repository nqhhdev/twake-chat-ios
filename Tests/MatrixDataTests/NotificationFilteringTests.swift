import Domain
import Foundation
import Testing

@testable import MatrixData

struct NotificationFilteringTests {
  @Test func aPlainMessageIsNotAnEdit() {
    let raw = #"{"type":"m.room.message","content":{"msgtype":"m.text","body":"Hi"}}"#
    #expect(!NotificationContentProxy.isEdit(rawEvent: raw))
  }

  @Test func anEditIsRecognised() {
    let raw = """
      {"type":"m.room.message","content":{"msgtype":"m.text","body":"* Hi",\
      "m.new_content":{"msgtype":"m.text","body":"Hi"},\
      "m.relates_to":{"rel_type":"m.replace","event_id":"$original"}}}
      """
    #expect(NotificationContentProxy.isEdit(rawEvent: raw))
  }

  @Test func anEditStillEncryptedIsRecognisedByItsClearRelation() {
    let raw = """
      {"type":"m.room.encrypted","content":{"algorithm":"m.megolm.v1.aes-sha2","ciphertext":"…",\
      "m.relates_to":{"rel_type":"m.replace","event_id":"$original"}}}
      """
    #expect(NotificationContentProxy.isEdit(rawEvent: raw))
  }

  @Test func aReplyOrAThreadMessageIsNotAnEdit() {
    let reply = #"{"content":{"m.relates_to":{"m.in_reply_to":{"event_id":"$a"}}}}"#
    let thread = #"{"content":{"m.relates_to":{"rel_type":"m.thread","event_id":"$a"}}}"#
    #expect(!NotificationContentProxy.isEdit(rawEvent: reply))
    #expect(!NotificationContentProxy.isEdit(rawEvent: thread))
  }

  @Test func unreadableJsonIsNotAnEdit() {
    #expect(!NotificationContentProxy.isEdit(rawEvent: ""))
    #expect(!NotificationContentProxy.isEdit(rawEvent: "[1]"))
  }

  @Test func aReactionAndARedactionAreSilent() {
    #expect(
      NotificationContentProxy.isSilent(.reactionContent(relatedEventId: "$a"), rawEvent: "{}"))
    #expect(
      NotificationContentProxy.isSilent(
        .roomRedaction(redactedEventId: "$a", reason: nil), rawEvent: "{}"))
  }

  @Test func aStickerAPollAndAnUndecryptedEventAreNotSilent() {
    #expect(!NotificationContentProxy.isSilent(.sticker, rawEvent: "{}"))
    #expect(!NotificationContentProxy.isSilent(.poll(question: "Lunch?"), rawEvent: "{}"))
    #expect(!NotificationContentProxy.isSilent(.roomEncrypted, rawEvent: "{}"))
  }

  @Test func whatThePushRulesFilterOutOrWasDeletedShowsNothing() {
    #expect(NotificationContentProxy.outcome(withoutEvent: .eventFilteredOut) == .hide)
    #expect(NotificationContentProxy.outcome(withoutEvent: .eventRedacted) == .hide)
  }

  @Test func anEventNotFoundKeepsTheGenericText() {
    #expect(NotificationContentProxy.outcome(withoutEvent: .eventNotFound) == .generic)
  }

  @Test func ownMessagesShowNothing() {
    #expect(NotificationContentProxy.isOwn(senderId: "@me:b", ownUserId: "@me:b"))
    #expect(!NotificationContentProxy.isOwn(senderId: "@alice:b", ownUserId: "@me:b"))
    #expect(!NotificationContentProxy.isOwn(senderId: "@me:b", ownUserId: nil))
    #expect(!NotificationContentProxy.isOwn(senderId: "", ownUserId: ""))
  }

  @Test func theSdkThreadIdWins() {
    let raw = #"{"content":{"m.relates_to":{"rel_type":"m.thread","event_id":"$other"}}}"#
    #expect(NotificationContentProxy.threadId("$root", rawEvent: raw) == "$root")
  }

  @Test func theThreadIdIsReadFromTheClearRelation() {
    let raw = """
      {"type":"m.room.encrypted","content":{"ciphertext":"…",\
      "m.relates_to":{"rel_type":"m.thread","event_id":"$root"}}}
      """
    #expect(NotificationContentProxy.threadId(nil, rawEvent: raw) == "$root")
    #expect(NotificationContentProxy.threadId("", rawEvent: raw) == "$root")
  }

  @Test func aReplyOrAnEditHasNoThread() {
    let reply = #"{"content":{"m.relates_to":{"m.in_reply_to":{"event_id":"$a"}}}}"#
    let edit = #"{"content":{"m.relates_to":{"rel_type":"m.replace","event_id":"$a"}}}"#
    #expect(NotificationContentProxy.threadId(nil, rawEvent: reply) == nil)
    #expect(NotificationContentProxy.threadId(nil, rawEvent: edit) == nil)
    #expect(NotificationContentProxy.threadId(nil, rawEvent: "") == nil)
  }

  @Test func aRingingCallBecomesARingThatExpiresWhenTheEventSays() throws {
    let ring = try #require(
      NotificationContentProxy.ring(
        of: .rtcNotification(
          notificationType: .ring, expirationTs: 1_700_000_030_000, callIntent: .audio),
        roomId: "!r:a", eventId: "$ring", roomName: "Team"))
    #expect(ring.roomId == "!r:a")
    #expect(ring.eventId == "$ring")
    #expect(ring.roomName == "Team")
    #expect(ring.isVoice)
    #expect(ring.expiresAt == Date(timeIntervalSince1970: 1_700_000_030))
  }

  @Test func aCallNoticeOrAnotherEventIsNoRing() {
    #expect(
      NotificationContentProxy.ring(
        of: .rtcNotification(notificationType: .notification, expirationTs: 1, callIntent: nil),
        roomId: "!r:a", eventId: "$e", roomName: "Team") == nil)
    #expect(
      NotificationContentProxy.ring(
        of: .sticker, roomId: "!r:a", eventId: "$e", roomName: "Team") == nil)
    #expect(
      NotificationContentProxy.ring(
        of: .rtcNotification(notificationType: .ring, expirationTs: 1, callIntent: .video),
        roomId: "", eventId: "$e", roomName: "Team") == nil)
  }

  @Test func aCallIsNamedByItsKind() {
    #expect(
      NotificationContentProxy.body(
        of: .rtcNotification(notificationType: .ring, expirationTs: 1, callIntent: .video))
        == "Incoming video call")
    #expect(
      NotificationContentProxy.body(
        of: .rtcNotification(notificationType: .ring, expirationTs: 1, callIntent: .audio))
        == "Incoming voice call")
    #expect(
      NotificationContentProxy.body(
        of: .rtcNotification(notificationType: .notification, expirationTs: 1, callIntent: nil))
        == "Started a call")
    #expect(
      NotificationContentProxy.isCall(
        .rtcNotification(notificationType: .ring, expirationTs: 1, callIntent: nil)))
    #expect(!NotificationContentProxy.isCall(.sticker))
  }
}
