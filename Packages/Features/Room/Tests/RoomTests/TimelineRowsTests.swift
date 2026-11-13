import Domain
import Foundation
import Testing

@testable import Room

struct TimelineRowsTests {
  private let start = Date(timeIntervalSince1970: 1_700_000_000)

  private func item(
    _ id: String, from sender: String, at seconds: TimeInterval,
    _ body: TimelineMessage.Body = .text("hi"),
    media: Bool = false
  ) -> TimelineItem {
    TimelineItem(
      id: id,
      kind: .message(
        TimelineMessage(
          eventId: "$\(id)", senderId: sender, senderName: sender, isOwn: false,
          date: start.addingTimeInterval(seconds), body: body,
          media: media ? MediaReference(source: id) : nil)))
  }

  private func positions(_ rows: [ChatRow]) -> [String: GroupPosition] {
    var result: [String: GroupPosition] = [:]
    for row in rows {
      switch row {
      case .message(let model): result[model.id] = model.position
      case .album(let model): result[model.id] = model.position
      case .other, .notices: continue
      }
    }
    return result
  }

  @Test func consecutiveMessagesOfOneSenderFormAGroup() {
    let rows = TimelineRows.rows(from: [
      item("1", from: "@a", at: 0), item("2", from: "@a", at: 30), item("3", from: "@a", at: 60),
    ])
    let positions = positions(rows)
    #expect(positions["1"] == GroupPosition(isFirst: true, isLast: false))
    #expect(positions["2"] == GroupPosition(isFirst: false, isLast: false))
    #expect(positions["3"] == GroupPosition(isFirst: false, isLast: true))
  }

  @Test func anotherSenderOrAPauseStartsANewGroup() {
    let rows = TimelineRows.rows(from: [
      item("1", from: "@a", at: 0), item("2", from: "@b", at: 10),
      item("3", from: "@b", at: 10 + 6 * 60),
    ])
    let positions = positions(rows)
    #expect(positions["1"] == .alone)
    #expect(positions["2"] == .alone)
    #expect(positions["3"] == .alone)
  }

  @Test func aDayDividerBreaksAGroup() {
    let divider = TimelineItem(id: "d", kind: .dayDivider(start))
    let rows = TimelineRows.rows(from: [
      item("1", from: "@a", at: 0), divider, item("2", from: "@a", at: 30),
    ])
    #expect(positions(rows)["2"] == .alone)
  }

  @Test func picturesSentTogetherFormAnAlbum() {
    let rows = TimelineRows.rows(from: [
      item("1", from: "@a", at: 0, .image(caption: nil), media: true),
      item("2", from: "@a", at: 5, .image(caption: nil), media: true),
      item("3", from: "@a", at: 9, .image(caption: "Holiday"), media: true),
      item("4", from: "@a", at: 20),
    ])
    #expect(rows.count == 2)
    guard case .album(let album) = rows[0] else {
      Issue.record("expected an album")
      return
    }
    #expect(album.messages.map(\.eventId) == ["$1", "$2", "$3"])
    #expect(album.caption == "Holiday")
    #expect(album.position == GroupPosition(isFirst: true, isLast: false))
  }

  @Test func aSinglePictureStaysAMessage() {
    let rows = TimelineRows.rows(from: [
      item("1", from: "@a", at: 0, .image(caption: nil), media: true)
    ])
    guard case .message = rows.first else {
      Issue.record("expected a message")
      return
    }
  }

  @Test func picturesFarApartAreNotAnAlbum() {
    let rows = TimelineRows.rows(from: [
      item("1", from: "@a", at: 0, .image(caption: nil), media: true),
      item("2", from: "@a", at: 120, .image(caption: nil), media: true),
    ])
    #expect(rows.allSatisfy { if case .message = $0 { true } else { false } })
  }

  @Test func anAlbumHoldsAtMostTenPictures() {
    let items = (0..<12).map {
      item("\($0)", from: "@a", at: Double($0), .image(caption: nil), media: true)
    }
    let rows = TimelineRows.rows(from: items)
    guard case .album(let first) = rows.first else {
      Issue.record("expected an album")
      return
    }
    #expect(first.messages.count == 10)
    #expect(rows.count == 2)
  }

  private func own(_ id: String, at seconds: TimeInterval, readers: Int = 0) -> TimelineItem {
    TimelineItem(
      id: id,
      kind: .message(
        TimelineMessage(
          eventId: "$\(id)", senderId: "@me", senderName: "Me", isOwn: true,
          date: start.addingTimeInterval(seconds), body: .text("hi"), readCount: readers)))
  }

  private func readIds(_ rows: [ChatRow]) -> [String] {
    rows.compactMap { row in
      if case .message(let model) = row, model.isRead { model.id } else { nil }
    }
  }

  @Test func aReceiptOnALaterMessageMarksTheEarlierOnesRead() {
    let rows = TimelineRows.rows(from: [
      own("1", at: 0), own("2", at: 10, readers: 1), own("3", at: 20),
    ])
    #expect(readIds(rows) == ["1", "2"])
  }

  @Test func aLaterMessageFromSomeoneElseMarksTheUsersMessagesRead() {
    let rows = TimelineRows.rows(from: [own("1", at: 0), item("2", from: "@bob", at: 10)])
    #expect(readIds(rows).contains("1"))
  }

  @Test func withoutReceiptsNothingIsRead() {
    let rows = TimelineRows.rows(from: [own("1", at: 0), own("2", at: 10)])
    #expect(readIds(rows).isEmpty)
  }

  private func notice(_ id: String) -> TimelineItem {
    TimelineItem(id: id, kind: .stateNotice("event \(id)"))
  }

  @Test func threeOrMoreRoomEventsInARowFoldIntoOneLine() {
    let rows = TimelineRows.rows(from: [
      notice("n1"), notice("n2"), notice("n3"), item("m", from: "@bob", at: 0), notice("n4"),
      notice("n5"),
    ])
    guard case .notices(let folded) = rows.first else {
      Issue.record("expected folded notices first")
      return
    }
    #expect(folded.id == "n1")
    #expect(folded.texts == ["event n1", "event n2", "event n3"])
    // Two events in a row stay as they are.
    #expect(rows.count == 4)
  }
}
