import Domain
import Foundation
import Observation

/// One room: its timeline, kept up to date, and the composer, as the Flutter app's `lib/pages/chat` shows them. The
/// composer sends Markdown text, replies to a message or edits one of the user's own; a message's menu reacts, copies or
/// deletes it. Message content is never logged.
@MainActor @Observable
public final class RoomViewModel {
  public enum State: Equatable {
    case loading
    case loaded([TimelineItem])
    case failed(String)
  }

  /// What the composer is doing besides sending a new message.
  public enum ComposerMode: Equatable {
    case new
    case reply(eventId: String, to: TimelineMessage.Reply)
    case edit(eventId: String)
  }

  public let roomId: String
  public let roomName: String
  public private(set) var state: State = .loading
  public var draft = ""
  public private(set) var composerMode: ComposerMode = .new
  public private(set) var isLoadingOlder = false
  public private(set) var reachedStart = false
  public private(set) var errorMessage: String?

  @ObservationIgnored private let repository: any TimelineRepository
  /// Loads the pictures and files of messages.
  @ObservationIgnored public let media: any MediaRepository
  @ObservationIgnored private let detailsRepository: (any RoomDetailsRepository)?
  @ObservationIgnored private let onLeft: @MainActor () -> Void
  @ObservationIgnored private var startCount = 0

  /// The quick reactions of the Flutter message menu.
  public static let quickReactions = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

  public init(
    roomId: String, roomName: String, repository: any TimelineRepository,
    media: any MediaRepository,
    details: (any RoomDetailsRepository)? = nil, onLeft: @escaping @MainActor () -> Void = {}
  ) {
    self.roomId = roomId
    self.roomName = roomName
    self.repository = repository
    self.media = media
    self.detailsRepository = details
    self.onLeft = onLeft
  }

  /// The details page of this room, or `nil` when the app gave no details repository.
  public func makeDetails() -> RoomDetailsViewModel? {
    detailsRepository.map { RoomDetailsViewModel(roomId: roomId, repository: $0, onLeft: onLeft) }
  }

  /// Opens the timeline and follows it until the calling task is cancelled (the screen goes away); then closes it.
  public func start() async {
    startCount += 1
    let thisStart = startCount
    state = .loading
    let items: AsyncStream<[TimelineItem]>
    do {
      items = try await repository.open()
    } catch {
      if thisStart == startCount { state = .failed("Could not open this chat.") }
      return
    }
    Task { await self.loadOlder() }
    await repository.markAsRead()
    for await list in items where thisStart == startCount {
      state = .loaded(list)
      if list.contains(where: { $0.kind == .timelineStart }) { reachedStart = true }
    }
    if thisStart == startCount { await repository.close() }
  }

  /// Loads older messages, once at a time, until the start of the room.
  public func loadOlder() async {
    guard !isLoadingOlder, !reachedStart else { return }
    isLoadingOlder = true
    defer { isLoadingOlder = false }
    do {
      reachedStart = try await repository.loadOlder()
    } catch {
      // Scrolling up again tries once more.
    }
  }

  public var canSend: Bool {
    !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Sends the draft as a new message, a reply or an edit; the draft is cleared at once and put back if sending fails.
  public func send() async {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    let mode = composerMode
    draft = ""
    composerMode = .new
    errorMessage = nil
    do {
      switch mode {
      case .new: try await repository.send(text: text)
      case .reply(let eventId, _): try await repository.reply(text: text, to: eventId)
      case .edit(let eventId): try await repository.edit(eventId: eventId, text: text)
      }
    } catch {
      draft = text
      composerMode = mode
      errorMessage = "Could not send your message. Please try again."
    }
  }

  public func reply(to message: TimelineMessage) {
    guard let eventId = message.eventId else { return }
    composerMode = .reply(
      eventId: eventId, to: .init(senderName: message.senderName, text: Self.text(of: message.body))
    )
  }

  /// Puts the user's own text message in the composer to edit it.
  public func edit(_ message: TimelineMessage) {
    guard message.isOwn, let eventId = message.eventId, case .text(let text) = message.body else {
      return
    }
    draft = text
    composerMode = .edit(eventId: eventId)
  }

  public func cancelComposerMode() {
    if case .edit = composerMode { draft = "" }
    composerMode = .new
  }

  public func delete(_ message: TimelineMessage) async {
    guard message.isOwn, let eventId = message.eventId else { return }
    do {
      try await repository.redact(eventId: eventId)
    } catch {
      errorMessage = "Could not delete the message."
    }
  }

  public func toggleReaction(_ key: String, on message: TimelineMessage) async {
    guard let eventId = message.eventId else { return }
    do {
      try await repository.toggleReaction(key, on: eventId)
    } catch {
      errorMessage = "Could not send the reaction."
    }
  }

  /// Saves a message's file in a temporary folder to open or share it; `nil` (with a message) when it cannot be loaded.
  public func file(of message: TimelineMessage) async -> URL? {
    guard let reference = message.media else { return nil }
    do {
      return try await media.file(reference, filename: Self.fileName(of: message))
    } catch {
      errorMessage = "Could not download the file."
      return nil
    }
  }

  /// The name a message's file is saved under.
  public static func fileName(of message: TimelineMessage) -> String {
    switch message.body {
    case .file(let name): name
    case .image: "image"
    case .video: "video"
    case .audio: "audio"
    default: "file"
    }
  }

  /// "1.2 MB" for a file's size, as the Flutter file bubble shows it.
  public static func sizeText(_ bytes: Int?) -> String? {
    bytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
  }

  /// The text a message's Copy action copies, or `nil` for a message without text.
  public static func text(of body: TimelineMessage.Body) -> String? {
    switch body {
    case .text(let text), .emote(let text), .notice(let text), .location(let text): text
    case .image(let caption), .video(let caption), .audio(let caption): caption
    case .file(let name): name
    case .poll(let question): question
    case .sticker, .redacted, .unableToDecrypt, .unsupported: nil
    }
  }

  /// The day divider's text, as the Flutter timeline writes it: "Today", "Yesterday", or the date.
  public static func dayTitle(_ date: Date, now: Date = .now, calendar: Calendar = .current)
    -> String
  {
    if calendar.isDate(date, inSameDayAs: now) { return "Today" }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
      calendar.isDate(date, inSameDayAs: yesterday)
    {
      return "Yesterday"
    }
    return date.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
  }
}
