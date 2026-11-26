import Domain
import Foundation
import Testing

@testable import MatrixData

final class IndexAccount: @unchecked Sendable {
  private let lock = NSLock()
  private var _location: MessageIndex.Location?

  init(_ location: MessageIndex.Location?) {
    _location = location
  }

  var location: MessageIndex.Location? {
    get { lock.withLock { _location } }
    set { lock.withLock { _location = newValue } }
  }
}

struct MessageIndexTests {
  private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "message-index-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func entry(
    _ id: String, _ text: String, room: String = "!a", at seconds: Double = 0
  ) -> MessageIndex.Entry {
    MessageIndex.Entry(
      eventId: id, roomId: room, senderId: "@bob:example.org", senderName: "Bob",
      date: Date(timeIntervalSince1970: seconds), text: text)
  }

  private func makeIndex(at url: URL, userId: String = "@me:example.org") -> (
    MessageIndex, IndexAccount
  ) {
    let account = IndexAccount(MessageIndex.Location(userId: userId, url: url))
    return (MessageIndex(location: { account.location }), account)
  }

  @Test func wordsAreFoundIgnoringCaseAccentsAndWordEnds() async throws {
    let url = try folder().appending(path: "index.sqlite3")
    let (index, _) = makeIndex(at: url)
    await index.record([
      entry("$1", "Déjeuner à midi", at: 1), entry("$2", "see you", at: 2),
      entry("$3", "dejeuner demain", room: "!b", at: 3),
    ])
    let all = await index.search("DEJ", roomId: nil)
    #expect(all.map(\.eventId) == ["$3", "$1"])
    #expect(all.first?.roomId == "!b")
    #expect(all.first?.senderName == "Bob")
    #expect(all.first?.date == Date(timeIntervalSince1970: 3))
    #expect(await index.search("dejeuner midi", roomId: nil).map(\.eventId) == ["$1"])
    #expect(await index.search("dejeuner", roomId: "!a").map(\.eventId) == ["$1"])
    #expect(await index.search("  ", roomId: nil).isEmpty)
    #expect(await index.search("\"", roomId: nil).isEmpty)
  }

  @Test func anEditReplacesTheTextAndARedactionRemovesIt() async throws {
    let (index, _) = makeIndex(at: try folder().appending(path: "index.sqlite3"))
    await index.record([entry("$1", "lunch at noon")])
    await index.record([entry("$1", "dinner at eight")])
    #expect(await index.search("lunch", roomId: nil).isEmpty)
    #expect(await index.search("dinner", roomId: nil).map(\.text) == ["dinner at eight"])
    await index.remove(eventIds: ["$1"])
    #expect(await index.search("dinner", roomId: nil).isEmpty)
  }

  @Test func anotherAccountOrADeletedStoreStartsEmpty() async throws {
    let first = try folder()
    let url = first.appending(path: "index.sqlite3")
    let (index, account) = makeIndex(at: url)
    await index.record([entry("$1", "secret plan")])
    #expect(await index.search("secret", roomId: nil).count == 1)
    let second = try folder()
    account.location = MessageIndex.Location(
      userId: "@other:example.org", url: second.appending(path: "index.sqlite3"))
    #expect(await index.search("secret", roomId: nil).isEmpty)
    account.location = MessageIndex.Location(userId: "@me:example.org", url: url)
    #expect(await index.search("secret", roomId: nil).count == 1)
    try FileManager.default.removeItem(at: first)
    #expect(await index.search("secret", roomId: nil).isEmpty)
    account.location = nil
    await index.record([entry("$2", "secret again")])
    #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
  }

  @Test func theMatchQueryQuotesEveryWordAsAPrefix() {
    #expect(MessageIndex.matchQuery("lunch  at") == #""lunch"* "at"*"#)
    #expect(MessageIndex.matchQuery("a\"b OR c") == #""a"* "b"* "OR"* "c"*"#)
    #expect(MessageIndex.matchQuery(" \" ") == nil)
  }

  @Test func onlySentMessagesWithTextAreIndexedAndRedactionsAreNoted() {
    func message(
      _ id: String?, _ body: TimelineMessage.Body, sent: TimelineMessage.SendState = .sent
    )
      -> TimelineItem
    {
      TimelineItem(
        id: id ?? "local",
        kind: .message(
          TimelineMessage(
            eventId: id, senderId: "@bob:example.org", senderName: "Bob", isOwn: false,
            date: Date(timeIntervalSince1970: 5), body: body, sendState: sent)))
    }
    let items = [
      message("$1", .text("hello")), message("$2", .image(caption: "beach")),
      message("$3", .image(caption: nil)), message("$4", .redacted),
      message("$5", .unableToDecrypt(.unknown)), message(nil, .text("sending")),
      message("$6", .text("failed"), sent: .failed), message("$7", .text("   ")),
      TimelineItem(id: "day", kind: .timelineStart),
    ]
    let (entries, redacted) = MessageIndex.entries(roomId: "!a", items: items)
    #expect(entries.map(\.eventId) == ["$1", "$2"])
    #expect(entries.map(\.text) == ["hello", "beach"])
    #expect(entries.first?.roomId == "!a")
    #expect(redacted == ["$4"])
  }

  @Test func serverAndDeviceResultsMergeNewestFirstWithoutDuplicates() {
    func result(_ id: String, _ seconds: Double) -> RoomSearchResult {
      RoomSearchResult(
        eventId: id, senderId: "@b:x", senderName: "B", date: Date(timeIntervalSince1970: seconds),
        text: "t", roomId: "!r")
    }
    let merged = RoomSearchProxy.merged(
      [result("$1", 1), result("$3", 3)], [result("$2", 2), result("$3", 3)])
    #expect(merged.map(\.eventId) == ["$3", "$2", "$1"])
  }
}
