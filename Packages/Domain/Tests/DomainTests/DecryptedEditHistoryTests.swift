import Domain
import Foundation
import Testing

struct DecryptedEditHistoryTests {
  private func event(_ id: String, _ body: String, at seconds: Double, by sender: String = "@a:s")
    -> MessageVersion.Decrypted
  {
    MessageVersion.Decrypted(
      id: id, senderId: sender, body: body, date: Date(timeIntervalSince1970: seconds))
  }

  @Test func theOriginalComesFirstThenTheEditsOldestFirstWithoutTheirMarker() {
    let versions = MessageVersion.versions(
      original: event("$o", "helo", at: 1),
      edits: [event("$2", "* hello all", at: 3), event("$1", "* hello", at: 2)])
    #expect(versions.map(\.id) == ["$o", "$1", "$2"])
    #expect(versions.map(\.text) == ["helo", "hello", "hello all"])
  }

  @Test func onlyTheOriginalSenderCanEdit() {
    let versions = MessageVersion.versions(
      original: event("$o", "mine", at: 1),
      edits: [event("$x", "* not yours", at: 2, by: "@b:s"), event("$1", "* still mine", at: 3)])
    #expect(versions.map(\.text) == ["mine", "still mine"])
  }

  @Test func aBodyWithoutTheMarkerIsKeptAndOnlyOneMarkerIsRemoved() {
    let versions = MessageVersion.versions(
      original: event("$o", "list", at: 1),
      edits: [event("$1", "no marker", at: 2), event("$2", "* * item", at: 3)])
    #expect(versions.map(\.text) == ["list", "no marker", "* item"])
  }

  @Test func theEditIdsAreReadFromTheRelationsChunk() {
    let relations: [String: Any] = [
      "chunk": [
        ["event_id": "$1", "type": "m.room.encrypted"],
        ["type": "m.room.encrypted"],
        ["event_id": "$2", "type": "m.room.encrypted"],
      ]
    ]
    #expect(MessageVersion.editIds(inRelations: relations) == ["$1", "$2"])
    #expect(MessageVersion.editIds(inRelations: [:]).isEmpty)
  }
}
