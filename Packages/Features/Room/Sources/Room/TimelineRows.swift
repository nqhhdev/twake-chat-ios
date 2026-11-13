import Domain
import Foundation

/// The rows the room screen draws, built from the timeline items as Telegram and iMessage group them: consecutive
/// messages of one sender within `groupInterval` form a group (the name on the first bubble, the avatar and the tail on
/// the last, tighter spacing inside), and consecutive pictures of one sender within `albumInterval` form an album, as
/// the Flutter app's `images_builder` shows several pictures sent together.
public enum ChatRow: Identifiable, Equatable {
  case message(MessageRowModel)
  case album(AlbumRowModel)
  case other(TimelineItem)

  public var id: String {
    switch self {
    case .message(let row): row.id
    case .album(let row): row.id
    case .other(let item): item.id
    }
  }
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
}

public struct AlbumRowModel: Equatable, Identifiable {
  /// The first picture's item id.
  public let id: String
  public let messages: [TimelineMessage]
  public let position: GroupPosition

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
  /// Pictures of one sender closer than this form one album.
  public static let albumInterval: TimeInterval = 60
  /// The most pictures one album holds; more start a new album.
  public static let albumLimit = 10

  public static func rows(from items: [TimelineItem]) -> [ChatRow] {
    // 1. Albums: runs of at least two pictures from one sender, each close to the previous one.
    var units: [Unit] = []
    for item in items {
      guard case .message(let message) = item.kind else {
        units.append(.other(item))
        continue
      }
      if isAlbumPicture(message), case .pictures(let id, var run)? = units.last,
        let previous = run.last, previous.senderId == message.senderId,
        message.date.timeIntervalSince(previous.date) < albumInterval, run.count < albumLimit
      {
        run.append(message)
        units[units.count - 1] = .pictures(id: id, run)
      } else if isAlbumPicture(message) {
        units.append(.pictures(id: item.id, [message]))
      } else {
        units.append(.message(id: item.id, message))
      }
    }
    // 2. Groups: a unit continues the previous one when the same sender sent it soon after.
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
        rows.append(.message(MessageRowModel(id: id, message: message, position: position)))
      case .pictures(let id, let run) where run.count == 1:
        rows.append(.message(MessageRowModel(id: id, message: run[0], position: position)))
      case .pictures(let id, let run):
        rows.append(.album(AlbumRowModel(id: id, messages: run, position: position)))
      }
    }
    return rows
  }

  private enum Unit {
    case message(id: String, TimelineMessage)
    case pictures(id: String, [TimelineMessage])
    case other(TimelineItem)

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

  /// A picture that can sit in an album: sent, with its media, and not a reply.
  private static func isAlbumPicture(_ message: TimelineMessage) -> Bool {
    guard case .image = message.body, message.media != nil, message.reply == nil else {
      return false
    }
    return true
  }
}
