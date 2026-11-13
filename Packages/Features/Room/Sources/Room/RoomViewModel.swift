import Domain
import Foundation
import Observation
import SwiftUI

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
  /// The room's picture, or `nil` when it has none.
  public let roomAvatar: MediaReference?
  public private(set) var state: State = .loading
  public var draft = ""
  /// The people picked from the @ suggestions, by the name the draft shows; sending turns each into a mention.
  public private(set) var mentions: [RoomMember] = []
  /// The room's members, loaded the first time the user types "@".
  public private(set) var members: [RoomMember] = []
  @ObservationIgnored private var didLoadMembers = false
  public private(set) var composerMode: ComposerMode = .new
  public private(set) var isLoadingOlder = false
  public private(set) var reachedStart = false
  public private(set) var errorMessage: String?
  /// The other members typing now, by name.
  public private(set) var typingNames: [String] = []
  /// How many attachments are uploading.
  public private(set) var uploadCount = 0
  /// The room's pinned messages, oldest pin first, and the one the banner shows.
  public private(set) var pinned: [TimelineMessage] = []
  public private(set) var pinnedIndex = 0
  /// A short confirmation shown after an action ("Forwarded").
  public private(set) var toast: String?
  /// The message a long press lifted into the actions layer; while it is set, taps on pictures do nothing, so the
  /// finger lifting after the long press does not also open the picture.
  var focus: MessageFocus?
  /// A message to scroll to once the timeline first shows (the room was opened from a link to it).
  @ObservationIgnored public var pendingEventId: String?
  /// What another app shared into this room, applied once the timeline shows.
  @ObservationIgnored private var pendingShare: IncomingShare?

  @ObservationIgnored private let repository: any TimelineRepository
  /// Loads the pictures and files of messages.
  @ObservationIgnored public let media: any MediaRepository
  @ObservationIgnored private let detailsRepository: (any RoomDetailsRepository)?
  @ObservationIgnored private let onLeft: @MainActor () -> Void
  /// The rooms a message can be forwarded to: the chat list's, given by the app (ADR 0005).
  @ObservationIgnored public let forwardTargets: @MainActor () -> [RoomSummary]
  /// The app's people picker, passed on to the details page.
  @ObservationIgnored private let invitePeople: InvitePeople?
  @ObservationIgnored private let contentTimeline: ContentTimeline?
  @ObservationIgnored private let openDirectChat: (@MainActor (String) async -> Bool)?
  @ObservationIgnored private let search: (any RoomSearchRepository)?
  /// Link previews from the homeserver; `nil` shows links without a card.
  @ObservationIgnored private let linkPreviews: (any LinkPreviewRepository)?
  /// Why encrypted messages may not show on this device, for the banner above the timeline; `nil` hides it.
  public private(set) var sessionWarning: SessionWarning?
  @ObservationIgnored private let checkSession: (@Sendable () async -> SessionWarning?)?
  /// Which room events the chat shows, from Settings; the rows follow a change at once.
  @ObservationIgnored private let display: @MainActor () -> ChatDisplaySettings
  /// The banner's action: the app opens Privacy & Security, where the session is verified or the key entered.
  @ObservationIgnored public var onFixSession: (@MainActor () -> Void)?
  /// The user left this chat: it shows read-only, with Rejoin in place of the composer.
  public private(set) var isArchived: Bool
  @ObservationIgnored private let rejoinRoom: (@MainActor () async -> Bool)?
  public private(set) var isRejoining = false
  @ObservationIgnored private var startCount = 0

  /// The quick reactions of the Flutter message menu.
  public static let quickReactions = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

  public init(
    roomId: String, roomName: String, roomAvatar: MediaReference? = nil,
    repository: any TimelineRepository, media: any MediaRepository,
    details: (any RoomDetailsRepository)? = nil, onLeft: @escaping @MainActor () -> Void = {},
    forwardTargets: @escaping @MainActor () -> [RoomSummary] = { [] },
    invitePeople: InvitePeople? = nil,
    contentTimeline: ContentTimeline? = nil,
    openDirectChat: (@MainActor (String) async -> Bool)? = nil,
    search: (any RoomSearchRepository)? = nil,
    isArchived: Bool = false, rejoin: (@MainActor () async -> Bool)? = nil,
    linkPreviews: (any LinkPreviewRepository)? = nil,
    checkSession: (@Sendable () async -> SessionWarning?)? = nil,
    display: @escaping @MainActor () -> ChatDisplaySettings = { ChatDisplaySettings() }
  ) {
    self.display = display
    self.checkSession = checkSession
    self.linkPreviews = linkPreviews
    self.search = search
    self.isArchived = isArchived
    self.rejoinRoom = rejoin
    self.invitePeople = invitePeople
    self.contentTimeline = contentTimeline
    self.openDirectChat = openDirectChat
    self.forwardTargets = forwardTargets
    self.roomId = roomId
    self.roomName = roomName
    self.roomAvatar = roomAvatar
    self.repository = repository
    self.media = media
    self.detailsRepository = details
    self.onLeft = onLeft
  }

  /// The details page of this room, or `nil` when the app gave no details repository.
  public func makeDetails() -> RoomDetailsViewModel? {
    detailsRepository.map {
      RoomDetailsViewModel(
        roomId: roomId, repository: $0, onLeft: onLeft, invitePeople: invitePeople,
        media: media, contentTimeline: contentTimeline, openDirectChat: openDirectChat,
        block: { [repository] userId in
          do {
            try await repository.ignore(userId: userId)
            return true
          } catch {
            return false
          }
        })
    }
  }

  /// Takes what another app shared: its text goes into the composer, to read and send; its files are sent, as if
  /// picked with "+". Before the timeline shows, it waits for it.
  public func receive(_ share: IncomingShare) {
    if case .loaded = state {
      Task { await apply(share) }
    } else {
      pendingShare = share
    }
  }

  private func apply(_ share: IncomingShare) async {
    if let text = share.text, !text.isEmpty {
      draft = draft.isEmpty ? text : draft + "\n" + text
    }
    for file in share.files {
      guard let loaded = AttachmentLoader.load(document: file) else { continue }
      await send(
        attachment: loaded.kind, fileURL: loaded.fileURL, mimeType: loaded.mimeType,
        size: loaded.size)
      AttachmentLoader.remove(loaded)
    }
    share.done()
  }

  /// Joins this left chat again; the composer comes back.
  public func rejoin() async {
    guard isArchived, let rejoinRoom, !isRejoining else { return }
    isRejoining = true
    defer { isRejoining = false }
    errorMessage = nil
    if await rejoinRoom() {
      withAnimation { isArchived = false }
    } else {
      errorMessage = "Could not join this chat again. It may need an invitation."
    }
  }

  /// The link a text message shows a card for (Flutter `TwakeLinkPreview`): its first web link, but not a Matrix
  /// link, which opens a chat in the app instead of a page.
  static func previewLink(in text: String) -> URL? {
    guard let url = RoomContentViewModel.firstLink(in: text) else { return nil }
    let host = url.host()?.lowercased() ?? ""
    return host == "matrix.to" ? nil : url
  }

  /// Asks again whether this session can read encrypted messages; the screen calls it when it shows and when the app
  /// comes back, and the app after Privacy & Security closes.
  public func refreshSessionWarning() async {
    guard let checkSession else { return }
    let warning = await checkSession()
    guard warning != sessionWarning else { return }
    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { sessionWarning = warning }
  }

  /// The card of a link, from the homeserver.
  func linkPreview(of url: URL) async -> LinkPreview? {
    await linkPreviews?.preview(of: url)
  }

  /// Whether the app gave a way to search inside the room.
  public var canSearch: Bool { search != nil || contentTimeline != nil }

  /// The search inside this room, or `nil` when the app gave no way to search.
  public func makeSearch() -> RoomSearchViewModel? {
    guard canSearch else { return nil }
    return RoomSearchViewModel(
      roomId: roomId, server: search, textTimeline: contentTimeline?(.text),
      isEncrypted: { [detailsRepository, roomId] in
        // Unknown counts as encrypted: the device search works in every chat.
        (try? await detailsRepository?.details(roomId: roomId))?.isEncrypted ?? true
      })
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
    let typing = Task { [repository] in
      for await names in await repository.typingMembers() {
        await MainActor.run { withTypingAnimation { self.typingNames = names } }
      }
    }
    defer { typing.cancel() }
    // The draft left in this room, here or on another device, comes back in the composer.
    if draft.isEmpty, let saved = await repository.loadDraft() { draft = saved }
    await repository.markAsRead()
    await loadPinned()
    for await list in items where thisStart == startCount {
      state = .loaded(list)
      if list.contains(where: { $0.kind == .timelineStart }) { reachedStart = true }
      if let target = pendingEventId, !list.isEmpty {
        pendingEventId = nil
        Task { await jump(toEvent: target, maxPages: 50) }
      }
      if let share = pendingShare {
        pendingShare = nil
        Task { await apply(share) }
      }
    }
    if thisStart == startCount {
      // An edit in progress is not a draft; a new message or a reply is kept for the next visit.
      if case .edit = composerMode {} else { await repository.saveDraft(draft) }
      await repository.close()
    }
  }

  /// Loads a picture (an avatar) as data; `nil` when it fails.
  public func picture(_ reference: MediaReference) async -> Data? {
    try? await media.thumbnail(reference, width: 96, height: 96)
  }

  /// Loads older messages, once at a time, until the start of the room.
  /// Loads one older page. Returns `false` only when the page failed; a call while a page is loading, or at the start
  /// of the room, does nothing and returns `true`.
  @discardableResult
  public func loadOlder() async -> Bool {
    guard !isLoadingOlder, !reachedStart else { return true }
    isLoadingOlder = true
    defer { isLoadingOlder = false }
    do {
      reachedStart = try await repository.loadOlder()
      return true
    } catch {
      // Scrolling up again tries once more.
      return false
    }
  }

  /// Loads older pages until the start of the room, while the calling task runs (the top spinner is on screen). A
  /// failed page waits longer before the next try.
  public func loadOlderWhileVisible() async {
    while !reachedStart, !Task.isCancelled {
      let loaded = await loadOlder()
      try? await Task.sleep(for: loaded ? .milliseconds(250) : .seconds(3))
    }
  }

  /// The rows the screen draws: messages grouped by sender, pictures sent together as albums, without the room events
  /// the chat settings hide.
  public var rows: [ChatRow] {
    guard case .loaded(let items) = state else { return [] }
    return TimelineRows.rows(from: display().visible(items))
  }

  /// Counts sent messages, so the send button and haptics react to each send.
  public private(set) var sendCount = 0

  /// The pinned message the banner shows now.
  public var currentPinned: TimelineMessage? {
    pinned.isEmpty ? nil : pinned[min(pinnedIndex, pinned.count - 1)]
  }

  public func loadPinned() async {
    pinned = await repository.pinnedMessages()
    pinnedIndex = max(0, pinned.count - 1)
  }

  /// The message the timeline scrolls to (a replied-to message, a pin), then clears.
  var scrollTarget: String?
  /// The row that briefly flashes after a jump, so the eye finds it.
  public private(set) var highlightedEventId: String?
  /// The sheet listing who reacted to, or has seen, a message.
  var peopleSheet: PeopleSheet?

  /// What the people sheet lists.
  struct PeopleSheet: Identifiable {
    let title: String
    let userIds: [String]
    var id: String { title + userIds.joined() }
  }

  /// The timeline item id of the message `eventId`, or `nil` when it is not loaded.
  func itemId(ofEvent eventId: String) -> String? {
    guard case .loaded(let items) = state else { return nil }
    return items.first {
      if case .message(let message) = $0.kind { message.eventId == eventId } else { false }
    }?.id
  }

  /// How many older pages a jump loads looking for its message before giving up.
  public static let maxPagesToFind = 10

  /// Scrolls to a message and flashes it, loading older messages first when it is not loaded yet, as far as
  /// `maxPages` pages (a search result may be further back than a reply).
  public func jump(toEvent eventId: String, maxPages: Int = maxPagesToFind) async {
    var pages = 0
    while rowId(containingEvent: eventId) == nil {
      // Not loaded yet: load older pages, as far as `maxPagesToFind`, as the Flutter app does for a reply.
      guard !reachedStart, pages < maxPages, await loadOlder() else {
        showToast("Could not find that message")
        return
      }
      pages += 1
      // The page reaches `rows` through the timeline stream, a moment after `loadOlder` returns.
      for _ in 0..<20 where rowId(containingEvent: eventId) == nil {
        try? await Task.sleep(for: .milliseconds(50))
      }
    }
    guard let id = rowId(containingEvent: eventId) else { return }
    scrollTarget = id
    highlightedEventId = eventId
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(1.6))
      if self?.highlightedEventId == eventId { self?.highlightedEventId = nil }
    }
  }

  /// The row that shows `eventId`: its own, or the album it belongs to.
  private func rowId(containingEvent eventId: String) -> String? {
    for row in rows {
      switch row {
      case .message(let model) where model.message.eventId == eventId: return row.id
      case .album(let model) where model.messages.contains(where: { $0.eventId == eventId }):
        return row.id
      default: continue
      }
    }
    return nil
  }

  /// Sends again what failed to send.
  public func retryFailedSends() async {
    await repository.retryFailedSends()
    showToast("Sending again")
  }

  /// Shows who sent a reaction.
  func showReactors(_ reaction: TimelineMessage.Reaction) {
    peopleSheet = PeopleSheet(title: "Reacted \(reaction.key)", userIds: reaction.senderIds)
  }

  /// The room's members, for names and pictures in the people sheets.
  func roomMembers() async -> [RoomMember] {
    if members.isEmpty, let detailsRepository {
      members = (try? await detailsRepository.members(roomId: roomId)) ?? []
    }
    return members
  }

  /// Shows who has seen a message.
  func showReaders(of message: TimelineMessage) {
    peopleSheet = PeopleSheet(title: "Seen by", userIds: message.readerIds)
  }

  /// The banner's tap: show the pin before this one, wrapping round, as Telegram cycles its pins.
  public func showPreviousPinned() {
    guard !pinned.isEmpty else { return }
    pinnedIndex = pinnedIndex == 0 ? pinned.count - 1 : pinnedIndex - 1
  }

  public func isPinned(_ message: TimelineMessage) -> Bool {
    pinned.contains { $0.eventId != nil && $0.eventId == message.eventId }
  }

  public func togglePin(_ message: TimelineMessage) async {
    guard let eventId = message.eventId else { return }
    let pin = !isPinned(message)
    do {
      try await repository.setPinned(pin, eventId: eventId)
      await loadPinned()
      showToast(pin ? "Pinned" : "Unpinned")
    } catch {
      errorMessage = "Could not pin the message."
    }
  }

  public func forward(_ message: TimelineMessage, to room: RoomSummary) async {
    guard let eventId = message.eventId else { return }
    do {
      try await repository.forward(eventId: eventId, to: room.id)
      showToast("Forwarded to \(room.name)")
    } catch {
      errorMessage = "Could not forward the message."
    }
  }

  private func showToast(_ text: String) {
    toast = text
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(2))
      if self?.toast == text { self?.toast = nil }
    }
  }

  /// "Alice is typing…", "Alice and Bob are typing…", "Alice and 2 others are typing…", or `nil`.
  public var typingText: String? {
    switch typingNames.count {
    case 0: nil
    case 1: "\(typingNames[0]) is typing…"
    case 2: "\(typingNames[0]) and \(typingNames[1]) are typing…"
    default: "\(typingNames[0]) and \(typingNames.count - 1) others are typing…"
    }
  }

  /// Tells the room the user is typing while the draft has text, and stopped once it is empty.
  public func draftDidChange(from old: String, to new: String) async {
    if new.isEmpty { mentions = [] }
    let wasTyping = !old.isEmpty
    let isTyping = !new.isEmpty
    guard wasTyping != isTyping else { return }
    await repository.setTyping(isTyping)
  }

  /// Uploads and sends a picked picture, video or file, as a reply when the composer is replying. The file at
  /// `fileURL` must stay until the upload ends; the caller removes it after.
  public func send(
    attachment kind: OutgoingAttachment.Kind, fileURL: URL, mimeType: String?, size: Int?,
    caption: String? = nil
  ) async {
    var replyTo: String?
    if case .reply(let eventId, _) = composerMode {
      replyTo = eventId
      composerMode = .new
    }
    errorMessage = nil
    uploadCount += 1
    sendCount += 1
    defer { uploadCount -= 1 }
    do {
      try await repository.sendAttachment(
        OutgoingAttachment(
          kind: kind, fileURL: fileURL, mimeType: mimeType, size: size, caption: caption,
          replyTo: replyTo))
    } catch {
      errorMessage = "Could not send the attachment. Please try again."
    }
  }

  /// Sends what the preview kept, one after another (pictures sent together show as an album), the caption with the
  /// last one, as the Flutter upload manager does. The composer's draft, which the preview offered as the caption, is
  /// cleared; the copied files are deleted once sent.
  func send(batch: [AttachmentLoader.Loaded], caption: String) async {
    let caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
    draft = ""
    for (index, item) in batch.enumerated() {
      let isLast = index == batch.count - 1
      await send(
        attachment: item.kind, fileURL: item.fileURL, mimeType: item.mimeType, size: item.size,
        caption: isLast && !caption.isEmpty ? caption : nil)
      AttachmentLoader.remove(item)
    }
  }

  public var canSend: Bool {
    !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Sends the draft as a new message, a reply or an edit; the draft is cleared at once and put back if sending fails.
  /// The text after "@" at the end of the draft, while the user is typing a mention; `nil` otherwise.
  public var mentionQuery: String? {
    guard let at = draft.lastIndex(of: "@") else { return nil }
    if at > draft.startIndex, !draft[draft.index(before: at)].isWhitespace { return nil }
    let query = draft[draft.index(after: at)...]
    guard !query.contains(where: \.isNewline), query.count <= 32 else { return nil }
    // A name can hold spaces; two spaces in a row end the mention.
    guard !query.contains("  ") else { return nil }
    return String(query)
  }

  /// The members whose name or Matrix id contains the mention query, at most six.
  public var mentionSuggestions: [RoomMember] {
    guard let query = mentionQuery?.lowercased() else { return [] }
    let found = members.filter { member in
      query.isEmpty || member.name.lowercased().contains(query)
        || member.id.lowercased().contains(query)
    }
    return Array(found.prefix(6))
  }

  /// Loads the members for the @ suggestions, once, when the user starts a mention.
  public func loadMembersIfNeeded() async {
    guard mentionQuery != nil, !didLoadMembers, let detailsRepository else { return }
    didLoadMembers = true
    members = (try? await detailsRepository.members(roomId: roomId)) ?? []
  }

  /// Replaces the "@query" at the end of the draft with "@Name " and remembers the person.
  public func pickMention(_ member: RoomMember) {
    guard let at = draft.lastIndex(of: "@") else { return }
    let name = Self.mentionName(member)
    draft = String(draft[..<at]) + "@" + name + " "
    if !mentions.contains(member) { mentions.append(member) }
  }

  /// The name a mention shows, without the characters Markdown links use.
  static func mentionName(_ member: RoomMember) -> String {
    member.name.filter { !"[]()".contains($0) }
  }

  /// Turns each picked "@Name" of `text` into a Markdown link to the person, which the data layer sends as a mention.
  static func applyingMentions(_ mentions: [RoomMember], to text: String) -> String {
    var result = text
    for member in mentions {
      let name = mentionName(member)
      result = result.replacingOccurrences(
        of: "@" + name, with: "[\(name)](https://matrix.to/#/\(member.id))")
    }
    return result
  }

  public func send() async {
    let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !typed.isEmpty else { return }
    let text = Self.applyingMentions(mentions, to: typed)
    let picked = mentions
    mentions = []
    let mode = composerMode
    sendCount += 1
    draft = ""
    await repository.setTyping(false)
    composerMode = .new
    errorMessage = nil
    do {
      switch mode {
      case .new: try await repository.send(text: text)
      case .reply(let eventId, _): try await repository.reply(text: text, to: eventId)
      case .edit(let eventId): try await repository.edit(eventId: eventId, text: text)
      }
    } catch {
      draft = typed
      mentions = picked
      composerMode = mode
      errorMessage = "Could not send your message. Please try again."
    }
  }

  /// Reports a message to the server's moderators.
  public func report(_ message: TimelineMessage, reason: String) async {
    guard let eventId = message.eventId else { return }
    let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    do {
      try await repository.report(eventId: eventId, reason: reason.isEmpty ? nil : reason)
      showToast("Reported")
    } catch {
      errorMessage = "Could not report the message. Please try again."
    }
  }

  /// Blocks the message's sender: nothing from them shows any more, in any room.
  public func block(_ message: TimelineMessage) async {
    do {
      try await repository.ignore(userId: message.senderId)
      showToast("Blocked \(message.senderName)")
    } catch {
      errorMessage = "Could not block \(message.senderName). Please try again."
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

/// Runs a change to the typing names with the animation the indicator uses.
@MainActor private func withTypingAnimation(_ change: () -> Void) {
  withAnimation(.spring(response: 0.3, dampingFraction: 0.8), change)
}

/// What another app shared into a room: text for the composer and files to send. `done` runs once they are sent, so
/// the app can delete its copies.
public struct IncomingShare {
  public let text: String?
  public let files: [URL]
  public let done: @MainActor () -> Void

  public init(text: String?, files: [URL], done: @escaping @MainActor () -> Void = {}) {
    self.text = text
    self.files = files
    self.done = done
  }
}
