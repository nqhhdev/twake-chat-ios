import Foundation

/// One row of a room's timeline, as the room screen shows it. Implemented from the SDK timeline in MatrixData; no SDK
/// type appears here (ADR 0006). Messages hold message content, so `description` leaves their text out (ADR 0009).
public struct TimelineItem: Sendable, Equatable, Identifiable {
  public enum Kind: Sendable, Equatable {
    case message(TimelineMessage)
    /// A divider before the first item of a day.
    case dayDivider(Date)
    /// Where the user stopped reading.
    case readMarker
    /// A room event shown as one line of text, such as a member joining or the name changing.
    case stateNotice(String)
    /// The start of the room: nothing older can be loaded.
    case timelineStart
  }

  /// Stable across updates of the same item.
  public let id: String
  public let kind: Kind

  public init(id: String, kind: Kind) {
    self.id = id
    self.kind = kind
  }
}

/// A message-like event: a message, a sticker, a poll, a redacted or an undecryptable event.
public struct TimelineMessage: Sendable, Equatable {
  public enum Body: Sendable, Equatable {
    case text(String)
    case emote(String)
    case notice(String)
    case image(caption: String?)
    case video(caption: String?)
    case audio(caption: String?)
    case file(name: String)
    case location(String)
    case sticker(String)
    case poll(question: String)
    /// The message was deleted.
    case redacted
    /// The keys to decrypt the message are missing.
    case unableToDecrypt
    case unsupported
  }

  public enum SendState: Sendable, Equatable {
    case sent
    case sending
    case failed
  }

  /// One reaction key with how many people sent it and whether the user is one of them.
  public struct Reaction: Sendable, Equatable, Identifiable {
    public let key: String
    public let count: Int
    public let includesOwn: Bool
    public var id: String { key }

    public init(key: String, count: Int, includesOwn: Bool) {
      self.key = key
      self.count = count
      self.includesOwn = includesOwn
    }
  }

  /// What a reply quotes: the original sender and a one-line preview, or `nil` text while it loads.
  public struct Reply: Sendable, Equatable {
    public let senderName: String
    public let text: String?

    public init(senderName: String, text: String?) {
      self.senderName = senderName
      self.text = text
    }
  }

  /// The server event id; `nil` while a local echo has not been sent.
  public let eventId: String?
  public let senderId: String
  public let senderName: String
  public let isOwn: Bool
  public let date: Date
  public let body: Body
  public let isEdited: Bool
  public let reactions: [Reaction]
  public let reply: Reply?
  public let sendState: SendState
  /// The picture, video, voice message, file or sticker of the message; `nil` for text.
  public let media: MediaReference?

  public init(
    eventId: String?, senderId: String, senderName: String, isOwn: Bool, date: Date, body: Body,
    isEdited: Bool = false, reactions: [Reaction] = [], reply: Reply? = nil,
    sendState: SendState = .sent, media: MediaReference? = nil
  ) {
    self.eventId = eventId
    self.senderId = senderId
    self.senderName = senderName
    self.isOwn = isOwn
    self.date = date
    self.body = body
    self.isEdited = isEdited
    self.reactions = reactions
    self.reply = reply
    self.sendState = sendState
    self.media = media
  }
}

extension TimelineItem: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    switch kind {
    case .message: "TimelineItem(id: \(id), message: <redacted>)"
    case .dayDivider(let date): "TimelineItem(id: \(id), dayDivider: \(date))"
    case .readMarker: "TimelineItem(id: \(id), readMarker)"
    case .stateNotice: "TimelineItem(id: \(id), stateNotice: <redacted>)"
    case .timelineStart: "TimelineItem(id: \(id), timelineStart)"
    }
  }
  public var debugDescription: String { description }
}
