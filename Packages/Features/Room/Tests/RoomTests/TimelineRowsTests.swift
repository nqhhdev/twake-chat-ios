import Domain
import Foundation
import Testing

@testable import Room

struct TimelineRowsTests {
  private let start = Date(timeIntervalSince1970: 1_700_000_000)

  private func item(
    _ id: String, from sender: String, at seconds: TimeInterval,
    _ body: TimelineMessage.Body = .text("hi"),
    media: Bool = false, batch: String? = nil, reply: Bool = false,
    sendState: TimelineMessage.SendState = .sent
  ) -> TimelineItem {
    TimelineItem(
      id: id,
      kind: .message(
        TimelineMessage(
          eventId: "$\(id)", senderId: sender, senderName: sender, isOwn: false,
          date: start.addingTimeInterval(seconds), body: body,
          reply: reply ? TimelineMessage.Reply(senderName: "@b", text: "hi") : nil,
          sendState: sendState, media: media ? MediaReference(source: id) : nil,
          batchId: batch)))
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

  @Test func theScrollButtonCountsWhatArrivedBelow() {
    let rows = TimelineRows.rows(from: [
      item("1", from: "@a", at: 0), item("2", from: "@b", at: 400), item("3", from: "@a", at: 800),
    ])
    #expect(ChatRow.incomingCount(after: "1", in: rows) == 2)
    #expect(ChatRow.incomingCount(after: "3", in: rows) == 0)
    #expect(ChatRow.incomingCount(after: nil, in: rows) == 0)
    #expect(ChatRow.incomingCount(after: "gone", in: rows) == 0)
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
      item("1", from: "@a", at: 0, .image(caption: nil), media: true, batch: "b"),
      item("2", from: "@a", at: 5, .image(caption: nil), media: true, batch: "b"),
      item("3", from: "@a", at: 9, .image(caption: "Holiday"), media: true, batch: "b"),
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
      item("1", from: "@a", at: 0, .image(caption: nil), media: true, batch: "b"),
      item("2", from: "@a", at: 120, .image(caption: nil), media: true, batch: "b"),
    ])
    #expect(rows.allSatisfy { if case .message = $0 { true } else { false } })
  }

  @Test func anAlbumHoldsAtMostTenPictures() {
    let items = (0..<12).map {
      item("\($0)", from: "@a", at: Double($0), .image(caption: nil), media: true, batch: "b")
    }
    let rows = TimelineRows.rows(from: items)
    guard case .album(let first) = rows.first else {
      Issue.record("expected an album")
      return
    }
    #expect(first.messages.count == 10)
    #expect(rows.count == 2)
  }

  /// Two sends a few seconds apart, four pictures each and the caption on the last of the second, are two albums: the
  /// batch key Twake web and Flutter write (`app.twake.chat.batch`) tells the sends apart, not the time.
  @Test func twoSendsCloseTogetherAreTwoAlbums() {
    let first = (0..<4).map {
      item("a\($0)", from: "@a", at: Double($0), .image(caption: nil), media: true, batch: "A")
    }
    let second = (0..<4).map {
      item(
        "b\($0)", from: "@a", at: Double(10 + $0), .image(caption: $0 == 3 ? "Trip" : nil),
        media: true, batch: "B")
    }
    let albums = TimelineRows.rows(from: first + second).compactMap { row in
      if case .album(let album) = row { album } else { nil }
    }
    #expect(albums.map(\.messages.count) == [4, 4])
    #expect(albums.map(\.caption) == [nil, "Trip"])
  }

  /// A picture with a batch key and one without are not of one send.
  @Test func aKeyedAndAKeylessPictureDoNotJoin() {
    let rows = TimelineRows.rows(from: [
      item("1", from: "@a", at: 0, .image(caption: nil), media: true, batch: "b"),
      item("2", from: "@a", at: 1, .image(caption: nil), media: true),
    ])
    #expect(rows.allSatisfy { if case .message = $0 { true } else { false } })
  }

  /// Two pictures sent one after the other carry no batch key: each stays a message of its own.
  @Test func picturesWithoutABatchKeyAreNotJoined() {
    let rows = TimelineRows.rows(from: [
      item("1", from: "@a", at: 0, .image(caption: nil), media: true),
      item("2", from: "@a", at: 2, .image(caption: nil), media: true),
    ])
    #expect(rows.count == 2)
    #expect(rows.allSatisfy { if case .message = $0 { true } else { false } })
  }

  /// As on web, the first picture of an album may be a reply; a reply later starts a new album.
  @Test func onlyTheFirstPictureMayBeAReply() {
    let rows = TimelineRows.rows(from: [
      item("1", from: "@a", at: 0, .image(caption: nil), media: true, batch: "b", reply: true),
      item("2", from: "@a", at: 1, .image(caption: nil), media: true, batch: "b"),
      item("3", from: "@a", at: 2, .image(caption: nil), media: true, batch: "b", reply: true),
      item("4", from: "@a", at: 3, .image(caption: nil), media: true, batch: "b"),
    ])
    let albums = rows.compactMap { row in
      if case .album(let album) = row { album.messages.map(\.eventId) } else { nil }
    }
    #expect(albums == [["$1", "$2"], ["$3", "$4"]])
  }

  /// As on web, only sent pictures join: one still sending shows on its own until it is sent.
  @Test func aPictureStillSendingDoesNotJoin() {
    let rows = TimelineRows.rows(from: [
      item("1", from: "@a", at: 0, .image(caption: nil), media: true),
      item("2", from: "@a", at: 1, .image(caption: nil), media: true, sendState: .sending),
    ])
    #expect(rows.allSatisfy { if case .message = $0 { true } else { false } })
  }

  /// Only the last picture of an album has a caption: a picture after a captioned one starts a new album.
  @Test func aCaptionEndsTheAlbum() {
    let rows = TimelineRows.rows(from: [
      item("1", from: "@a", at: 0, .image(caption: nil), media: true, batch: "b"),
      item("2", from: "@a", at: 1, .image(caption: "One"), media: true, batch: "b"),
      item("3", from: "@a", at: 2, .image(caption: nil), media: true, batch: "b"),
      item("4", from: "@a", at: 3, .image(caption: nil), media: true, batch: "b"),
    ])
    let albums = rows.compactMap { row in
      if case .album(let album) = row { album.messages.map(\.eventId) } else { nil }
    }
    #expect(albums == [["$1", "$2"], ["$3", "$4"]])
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

  @Test func aPictureJustSentShowsFromTheUploadedCopy() {
    func picture(own: Bool, age: TimeInterval, _ body: TimelineMessage.Body = .image(caption: nil))
      -> TimelineMessage
    {
      TimelineMessage(
        eventId: "$1", senderId: "@a", senderName: "A", isOwn: own,
        date: start.addingTimeInterval(-age), body: body)
    }
    #expect(MessageMediaView.wasJustSent(picture(own: true, age: 30), now: start))
    #expect(!MessageMediaView.wasJustSent(picture(own: true, age: 3600), now: start))
    #expect(!MessageMediaView.wasJustSent(picture(own: false, age: 30), now: start))
    #expect(
      !MessageMediaView.wasJustSent(picture(own: true, age: 30, .file(name: "a.pdf")), now: start))
    #expect(
      RemoteImage.fill(CGSize(width: 4000, height: 2000), CGSize(width: 400, height: 400)).height
        == 400)
    #expect(
      RemoteImage.fill(CGSize(width: 100, height: 100), CGSize(width: 400, height: 400)).width
        == 100)
  }

  /// A scroll offset left outside the content (after the SDK refilled the list, or the keyboard resized the view)
  /// shows an empty screen; the timeline then returns to the newest message.
  @Test func aViewportOutsideTheContentShowsNothing() {
    func visible(from y: CGFloat) -> CGRect { CGRect(x: 0, y: y, width: 400, height: 600) }
    #expect(TimelineScroll.showsNothing(visible: visible(from: 900), contentHeight: 800))
    #expect(TimelineScroll.showsNothing(visible: visible(from: -700), contentHeight: 800))
    #expect(!TimelineScroll.showsNothing(visible: visible(from: 200), contentHeight: 800))
    // Pulled past the end, some content still shows.
    #expect(!TimelineScroll.showsNothing(visible: visible(from: 260), contentHeight: 800))
    // Content shorter than the screen, and no content at all.
    #expect(!TimelineScroll.showsNothing(visible: visible(from: 0), contentHeight: 120))
    #expect(!TimelineScroll.showsNothing(visible: visible(from: 0), contentHeight: 0))
  }
}
