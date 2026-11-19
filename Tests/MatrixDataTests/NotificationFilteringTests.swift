import Domain
import Testing

@testable import MatrixData

/// Which pushes show nothing: edits, reactions, redactions, and what the SDK filters out or finds deleted; a failure
/// keeps the generic text (ADR 0009). The SDK values are implicit enum members, so this file does not import the SDK
/// (ADR 0006, scripts/check-architecture.sh rule 1). A `.roomMessage` needs the SDK's struct initializers, which this
/// bundle does not link, so the edit check is tested on the event's JSON, the input `isSilent` hands it.
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
}
