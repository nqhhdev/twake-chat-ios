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

  /// Which chat setting can hide an item (Flutter `EventVisibilityGroup`).
  public enum Visibility: Sendable, Equatable {
    /// Messages and the room events that matter: always shown.
    case always
    /// A room setting changed, such as encryption, the description or the permissions.
    case unimportant
    /// An event the app cannot show as anything more than its type.
    case unknown
  }

  /// Stable across updates of the same item.
  public let id: String
  public let kind: Kind
  public let visibility: Visibility

  public init(id: String, kind: Kind, visibility: Visibility = .always) {
    self.id = id
    self.kind = kind
    self.visibility = visibility
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
    /// The Matrix ids of the people who sent it, oldest first.
    public let senderIds: [String]
    public var id: String { key }

    public init(key: String, count: Int, includesOwn: Bool, senderIds: [String] = []) {
      self.key = key
      self.count = count
      self.includesOwn = includesOwn
      self.senderIds = senderIds
    }
  }

  /// What a reply quotes: the original sender and a one-line preview, or `nil` text while it loads.
  /// A thread started on this message (`m.thread`): how many replies it has and the latest one, as its root shows.
  public struct ThreadPreview: Sendable, Equatable {
    public let replyCount: Int
    public let latestSenderName: String?
    public let latestText: String?

    public init(replyCount: Int, latestSenderName: String? = nil, latestText: String? = nil) {
      self.replyCount = replyCount
      self.latestSenderName = latestSenderName
      self.latestText = latestText
    }
  }

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
  /// A text of only emojis, which the room shows large and without a bubble, as iMessage and Telegram do.
  public let isEmojiOnly: Bool
  /// The sender's picture, or `nil` when they have none.
  public let senderAvatar: MediaReference?
  /// How many people other than the user have their read receipt on this message. A receipt sits on the newest
  /// message a person has read only, so a message is read when it or any later message has one.
  public let readCount: Int
  /// The Matrix ids of those people.
  public let readerIds: [String]
  /// The event the message replies to, so the room can jump to it.
  public let replyToEventId: String?
  /// The text, emote or notice as its sender formatted it (bold, links, mentions, quotes, lists), from its HTML body;
  /// `nil` when it has none, and the plain `body` shows.
  public let formatted: AttributedString?
  /// How much of the picture, video or file is uploaded (0…1) while it is sending; `nil` otherwise.
  public let uploadProgress: Double?
  /// The poll, its answers and votes, for a `.poll` body.
  public let poll: Poll?
  /// The thread started on this message, or `nil` when it has none.
  public let thread: ThreadPreview?
  /// The root of the thread this message is a reply in, or `nil` when it is in the room's main timeline.
  public let threadRootId: String?

  public init(
    eventId: String?, senderId: String, senderName: String, isOwn: Bool, date: Date, body: Body,
    isEdited: Bool = false, reactions: [Reaction] = [], reply: Reply? = nil,
    sendState: SendState = .sent, media: MediaReference? = nil, isEmojiOnly: Bool = false,
    senderAvatar: MediaReference? = nil, readCount: Int = 0, readerIds: [String] = [],
    replyToEventId: String? = nil, formatted: AttributedString? = nil,
    uploadProgress: Double? = nil, poll: Poll? = nil, thread: ThreadPreview? = nil,
    threadRootId: String? = nil
  ) {
    self.thread = thread
    self.threadRootId = threadRootId
    self.poll = poll
    self.uploadProgress = uploadProgress
    self.formatted = formatted
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
    self.isEmojiOnly = isEmojiOnly
    self.senderAvatar = senderAvatar
    self.readCount = readCount
    self.readerIds = readerIds
    self.replyToEventId = replyToEventId
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
