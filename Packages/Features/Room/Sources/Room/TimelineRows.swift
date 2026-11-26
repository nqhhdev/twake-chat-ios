import Domain
import Foundation

/// The rows the room screen draws, built from the timeline items as Telegram and iMessage group them: consecutive
/// messages of one sender within `groupInterval` form a group (the name on the first bubble, the avatar and the tail on
/// the last, tighter spacing inside), and the pictures one person sent together form an album, with the rules of
/// Twake web (`groupAlbums`) but stricter: one sender, the same batch key (`TimelineMessage.batchId`; pictures without a
/// key were not sent together and stay single messages), each within
/// `albumInterval` of the previous one, the caption only on the last and a reply only on the first.
public enum ChatRow: Identifiable, Equatable {
  case message(MessageRowModel)
  case album(AlbumRowModel)
  case other(TimelineItem)
  /// Room events in a row ("joined", "changed the avatar"…), folded into one line the user can open.
  case notices(NoticesRowModel)

  public var id: String {
    switch self {
    case .message(let row): row.id
    case .album(let row): row.id
    case .other(let item): item.id
    case .notices(let row): row.id
    }
  }
}

extension ChatRow {
  /// How many messages from other people sit below the row `id`: what arrived since the user scrolled up from it,
  /// shown on the scroll-down button as Flutter and the web do. `0` when the row is no longer in the list.
  public static func incomingCount(after id: String?, in rows: [ChatRow]) -> Int {
    guard let id, let index = rows.firstIndex(where: { $0.id == id }) else { return 0 }
    return rows[(index + 1)...].reduce(0) { count, row in
      switch row {
      case .message(let row): count + (row.message.isOwn ? 0 : 1)
      case .album(let row): count + (row.messages.first?.isOwn == false ? row.messages.count : 0)
      case .other, .notices: count
      }
    }
  }
}

/// Consecutive room events shown as one foldable line.
public struct NoticesRowModel: Equatable, Identifiable {
  /// The newest event's item id, so prepending older notices keeps this row's identity.
  public let id: String
  public let texts: [String]
}

/// Where a bubble sits in its sender's group.
public struct GroupPosition: Equatable, Sendable {
  public let isFirst: Bool
  public let isLast: Bool

  public init(isFirst: Bool, isLast: Bool) {
    self.isFirst = isFirst
    self.isLast = isLast
  }

  public static let alone = GroupPosition(isFirst: true, isLast: true)
}

public struct MessageRowModel: Equatable, Identifiable {
  public let id: String
  public let message: TimelineMessage
  public let position: GroupPosition
  /// Someone else has read up to this message or past it; the user's own messages show a double tick.
  public var isRead = false
}

public struct AlbumRowModel: Equatable, Identifiable {
  /// The album's batch id, or the first picture's item id when there is no batch.
  public let id: String
  public let messages: [TimelineMessage]
  public let position: GroupPosition
  /// Someone else has read up to this album or past it.
  public var isRead = false

  /// The caption of the album: the last caption one of its pictures has.
  public var caption: String? {
    messages.lazy.reversed().compactMap { message -> String? in
      if case .image(let caption?) = message.body,
        !caption.trimmingCharacters(in: .whitespaces).isEmpty
      {
        return caption
      }
      return nil
    }.first
  }
}

public enum TimelineRows {
  /// Messages of one sender closer than this stay in one group.
  public static let groupInterval: TimeInterval = 5 * 60
  /// Pictures further apart than this do not join.
  public static let albumInterval: TimeInterval = 60
  /// The most pictures one album holds; more start a new album.
  public static let albumLimit = 10

  public static func rows(from items: [TimelineItem], gifsOff: Bool = false) -> [ChatRow] {
    // 1. Albums: runs of at least two pictures sent together.
    var units: [Unit] = []
    for item in items {
      guard case .message(let message) = item.kind else {
        units.append(.other(item))
        continue
      }
      let isPicture =
        isAlbumPicture(message) && !RoomViewModel.isHiddenGif(message, gifsOff: gifsOff)
      if isPicture, case .pictures(let id, var run)? = units.last,
        let previous = run.last, canJoin(message, after: previous, runCount: run.count)
      {
        run.append(message)
        units[units.count - 1] = .pictures(id: id, run)
      } else if isPicture {
        // batchId stays the same when an older picture of the same send is prepended, so the row id does not change.
        units.append(.pictures(id: message.batchId ?? item.id, [message]))
      } else {
        units.append(.message(id: item.id, message))
      }
    }
    // 2. Read: someone else read a unit when a receipt of theirs sits on it or on a later message, or when they
    // wrote a later message.
    var isRead = Array(repeating: false, count: units.count)
    var readLater = false
    for (index, unit) in units.enumerated().reversed() {
      readLater = readLater || unit.messages.contains { $0.readCount > 0 || !$0.isOwn }
      isRead[index] = readLater
    }
    // 3. Groups: a unit continues the previous one when the same sender sent it soon after.
    var rows: [ChatRow] = []
    for (index, unit) in units.enumerated() {
      let previous = index > 0 ? units[index - 1] : nil
      let next = index + 1 < units.count ? units[index + 1] : nil
      let position = GroupPosition(
        isFirst: !continues(unit, after: previous), isLast: !continues(next, after: unit))
      switch unit {
      case .other(let item):
        rows.append(.other(item))
      case .message(let id, let message):
        rows.append(
          .message(
            MessageRowModel(id: id, message: message, position: position, isRead: isRead[index])))
      case .pictures(let id, let run) where run.count == 1:
        rows.append(
          .message(
            MessageRowModel(id: id, message: run[0], position: position, isRead: isRead[index])))
      case .pictures(let id, let run):
        rows.append(
          .album(AlbumRowModel(id: id, messages: run, position: position, isRead: isRead[index])))
      }
    }
    return foldingNotices(in: rows)
  }

  /// Runs of at least this many room events fold into one line.
  public static let noticeFoldMinimum = 3

  /// Folds each run of `noticeFoldMinimum` or more consecutive room events into one `.notices` row.
  static func foldingNotices(in rows: [ChatRow]) -> [ChatRow] {
    var result: [ChatRow] = []
    var run: [TimelineItem] = []
    func flush() {
      if run.count >= noticeFoldMinimum {
        let texts = run.compactMap { item -> String? in
          if case .stateNotice(let text) = item.kind { text } else { nil }
        }
        // The newest event's id, so prepending an older notice does not change the row.
        result.append(.notices(NoticesRowModel(id: run[run.count - 1].id, texts: texts)))
      } else {
        result.append(contentsOf: run.map(ChatRow.other))
      }
      run = []
    }
    for row in rows {
      if case .other(let item) = row, case .stateNotice = item.kind {
        run.append(item)
      } else {
        flush()
        result.append(row)
      }
    }
    flush()
    return result
  }

  private enum Unit {
    case message(id: String, TimelineMessage)
    case pictures(id: String, [TimelineMessage])
    case other(TimelineItem)

    var messages: [TimelineMessage] {
      switch self {
      case .message(_, let message): [message]
      case .pictures(_, let run): run
      case .other: []
      }
    }

    var first: TimelineMessage? {
      switch self {
      case .message(_, let message): message
      case .pictures(_, let run): run.first
      case .other: nil
      }
    }

    var last: TimelineMessage? {
      switch self {
      case .message(_, let message): message
      case .pictures(_, let run): run.last
      case .other: nil
      }
    }
  }

  private static func continues(_ unit: Unit?, after previous: Unit?) -> Bool {
    guard let current = unit?.first, let before = previous?.last else { return false }
    return current.senderId == before.senderId
      && current.date.timeIntervalSince(before.date) < groupInterval
  }

  /// Whether `message` continues the album of `runCount` pictures that `previous` ends, as Twake web joins them:
  /// `previous` has no caption (a send puts it on its last picture) and is a reply only as the first picture,
  /// `message` is no reply, both carry the same batch key, one sender, close in time. Two pictures without a key are
  /// not joined: only a key says they were picked and sent together. Day dividers and the
  /// read marker sit between the pictures as other rows, so they end the album as web's day and unread breaks do.
  private static func canJoin(
    _ message: TimelineMessage, after previous: TimelineMessage, runCount: Int
  ) -> Bool {
    runCount < albumLimit && !hasCaption(previous) && (previous.reply == nil || runCount == 1)
      && message.reply == nil && message.batchId != nil && message.batchId == previous.batchId
      && message.senderId == previous.senderId
      && message.date.timeIntervalSince(previous.date) <= albumInterval
  }

  private static func hasCaption(_ message: TimelineMessage) -> Bool {
    guard case .image(let caption) = message.body else { return false }
    return caption?.isEmpty == false
  }

  /// A picture that can sit in an album, as on web: sent (one still sending shows alone), with its media, and in the
  /// room's main timeline.
  private static func isAlbumPicture(_ message: TimelineMessage) -> Bool {
    guard case .image = message.body, message.media != nil, message.sendState == .sent,
      message.threadRootId == nil
    else { return false }
    return true
  }
}

extension ChatRow {
  /// The message picked when this row is tapped in selection mode: a sent message, or the last picture of an album.
  var selectableMessage: TimelineMessage? {
    switch self {
    case .message(let model): model.message.eventId == nil ? nil : model.message
    case .album(let model): model.messages.last
    case .other, .notices: nil
    }
  }
}
