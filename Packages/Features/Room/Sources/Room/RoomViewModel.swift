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
  public private(set) var roomName: String
  /// The root of the thread this screen shows, or `nil` for the room's main timeline.
  public let threadRootId: String?
  /// The thread pushed from this room, while it shows.
  public var openedThread: RoomViewModel?
  @ObservationIgnored private let threadTimeline: ThreadTimeline?
  /// The room's picture, or `nil` when it has none.
  public private(set) var roomAvatar: MediaReference?
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
  /// How far the timeline loads older pages by itself.
  public var historyLoading = HistoryLoading()
  /// The top of the timeline must leave the viewport before another page can be asked for (one trigger, one page).
  private var topArmed = true
  /// Loading by itself stopped (`HistoryLoading`): the top of the timeline offers "Load earlier messages".
  public private(set) var isHistoryPaused = false
  /// A list of this timeline held the start of the room; a later list without it means the SDK reset the timeline.
  @ObservationIgnored private var sawTimelineStart = false
  public private(set) var errorMessage: String?
  /// The other members typing now, by name.
  public private(set) var typingNames: [String] = []
  /// How many attachments are uploading.
  public private(set) var uploadCount = 0
  /// The room's pinned messages, oldest pin first, and the one the banner shows.
  public private(set) var pinned: [TimelineMessage] = []
  public private(set) var pinnedIndex = 0
  /// The user may delete other people's messages, as a moderator; loaded with the timeline.
  public private(set) var canRedactOthers = false
  @ObservationIgnored private let saved: (any SavedMessagesRepository)?
  @ObservationIgnored let threadPrefs: (any ThreadPrefsRepository)?
  /// On a thread's screen: what the user chose for it, shared with the web app; `nil` when nothing was chosen.
  var threadPref: ThreadPref?
  /// The commands of the room's bots, loaded with the timeline.
  public private(set) var botCommands: [BotCommand] = []

  /// The message whose edit history the sheet shows.
  public var historyMessage: TimelineMessage?
  /// The files a message menu's Share downloaded; the share sheet also saves them to Photos or Files.
  var sharedFiles: DownloadedFiles?
  /// Share is downloading; the screen shows a spinner until the sheet opens.
  private(set) var isPreparingShare = false

  /// The versions of an edited message, the original first; `nil` in an encrypted chat.
  func editHistory(of message: TimelineMessage) async -> [MessageVersion]? {
    guard let eventId = message.eventId else { return [] }
    return await repository.editHistory(of: eventId)
  }

  /// The commands the draft's "/" word may become.
  public var commandSuggestions: [BotCommand] {
    Array(BotCommand.matching(draft, in: botCommands).prefix(6))
  }

  /// Writes the command's name in the composer, ready for its arguments.
  public func pick(_ command: BotCommand) {
    draft = "/" + command.name + (command.argumentNames.isEmpty ? "" : " ")
  }
  /// The event ids of this room's messages the user saved.
  public private(set) var savedEventIds: Set<String> = []
  public var canSave: Bool { saved != nil }

  func loadSaved() async {
    guard let saved else { return }
    savedEventIds = Set(await saved.savedRefs().filter { $0.roomId == roomId }.map(\.eventId))
  }

  public func isSaved(_ message: TimelineMessage) -> Bool {
    message.eventId.map(savedEventIds.contains) ?? false
  }

  /// Saves the message to Saved messages, or forgets it.
  public func toggleSaved(_ message: TimelineMessage) async {
    guard let saved, let eventId = message.eventId else { return }
    let save = !savedEventIds.contains(eventId)
    do {
      try await saved.setSaved(save, roomId: roomId, eventId: eventId)
      if save { savedEventIds.insert(eventId) } else { savedEventIds.remove(eventId) }
      showToast(save ? "Saved" : "Removed from saved messages")
    } catch {
      errorMessage = "Could not update your saved messages."
    }
  }

  /// On a thread's screen, the choice the user made for it (`Threads.swift`).
  func loadThreadPref() async {
    guard let threadRootId, let threadPrefs else { return }
    threadPref =
      await threadPrefs.threadPrefs()
      .first { $0.roomId == roomId && $0.threadId == threadRootId }?.pref
  }

  /// Saves the choice for this thread; it shows only once the server took it.
  public func setThreadPref(_ pref: ThreadPref) async {
    guard let threadRootId, let threadPrefs else { return }
    do {
      try await threadPrefs.setThreadPref(pref, roomId: roomId, threadId: threadRootId)
      threadPref = pref
      switch pref {
      case .follow: showToast("Following this thread")
      case .unfollow: showToast("You no longer follow this thread")
      case .mute: showToast("Thread muted")
      }
    } catch {
      errorMessage = "Could not update this thread."
    }
  }

  /// Members whose identity changed, for the banner above the timeline.
  public private(set) var identityWarnings: [IdentityWarning] = []

  /// Accepts a member's new identity; the banner goes away.
  public func accept(_ warning: IdentityWarning) async {
    do {
      try await repository.accept(warning)
      withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
        identityWarnings.removeAll { $0.userId == warning.userId }
      }
    } catch {
      errorMessage = "Could not update \(warning.name)'s identity."
    }
  }

  /// The room that replaced this one; the composer gives way to a banner that opens it.
  public private(set) var successorRoomId: String?
  /// The other person of this direct chat, when the user blocked them; the composer gives way to Unblock.
  public private(set) var blockedUserId: String?
  /// The user may post in this room; in a Broadcast only moderators do, and the composer gives way to a note.
  public private(set) var canSendMessages = true

  /// The other person of this direct chat, when it has one.
  @ObservationIgnored private var directUserId: String?
  /// Whether the user blocked someone, and unblocking them; given by the app from the account settings.
  @ObservationIgnored private let blocking: Blocking?

  /// The account's block list, as the room needs it.
  public struct Blocking: Sendable {
    public let isBlocked: @Sendable (String) async -> Bool
    public let unblock: @Sendable (String) async -> Bool

    public init(
      isBlocked: @escaping @Sendable (String) async -> Bool,
      unblock: @escaping @Sendable (String) async -> Bool
    ) {
      self.isBlocked = isBlocked
      self.unblock = unblock
    }
  }
  /// A short confirmation shown after an action ("Forwarded").
  public private(set) var toast: String?
  /// The message a long press lifted into the actions layer; while it is set, taps on pictures do nothing, so the
  /// finger lifting after the long press does not also open the picture.
  var focus: MessageFocus?
  /// A message to scroll to once the timeline first shows (the room was opened from a link to it).
  @ObservationIgnored public var pendingEventId: String?
  /// What another app shared into this room, applied once the timeline shows.
  @ObservationIgnored private var pendingShare: IncomingShare?

  @ObservationIgnored let repository: any TimelineRepository
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

  /// The tapback bar: the user's recent reactions first, then the defaults, six in all.
  public private(set) var reactionBar: [String] = RoomViewModel.quickReactions

  static func reactionBar(recents: [String]) -> [String] {
    var bar: [String] = []
    for key in recents + quickReactions where !bar.contains(key) && !key.isEmpty {
      bar.append(key)
      if bar.count == quickReactions.count { break }
    }
    return bar
  }

  func loadRecentReactions() async {
    reactionBar = Self.reactionBar(recents: await repository.recentReactions())
  }

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
    display: @escaping @MainActor () -> ChatDisplaySettings = { ChatDisplaySettings() },
    blocking: Blocking? = nil,
    saved: (any SavedMessagesRepository)? = nil,
    threadTimeline: ThreadTimeline? = nil, threadRootId: String? = nil,
    threadPrefs: (any ThreadPrefsRepository)? = nil
  ) {
    self.threadPrefs = threadPrefs
    self.threadTimeline = threadTimeline
    self.threadRootId = threadRootId
    self.saved = saved
    self.blocking = blocking
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

  var hasThreadTimelines: Bool { threadTimeline != nil }

  /// The screen of one thread of this room: the same room, on that thread's timeline, where what is sent goes into
  /// the thread. It has no thread of its own and no room search.
  func makeThread(root eventId: String) -> RoomViewModel? {
    guard let threadTimeline else { return nil }
    return RoomViewModel(
      roomId: roomId, roomName: roomName, roomAvatar: roomAvatar,
      repository: threadTimeline(eventId), media: media, details: detailsRepository, onLeft: onLeft,
      forwardTargets: forwardTargets, invitePeople: invitePeople, contentTimeline: nil,
      openDirectChat: openDirectChat, search: nil, isArchived: isArchived, rejoin: nil,
      linkPreviews: linkPreviews, checkSession: nil, display: display, blocking: blocking,
      saved: saved, threadTimeline: nil, threadRootId: eventId, threadPrefs: threadPrefs)
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
    await linkPreviews?.preview(of: url, inRoom: roomId)
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
  /// How long to wait after a `roomNotFound` or `unavailable` before opening the timeline again (cold start, #84).
  public var openRetryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]

  public func start() async {
    startCount += 1
    let thisStart = startCount
    state = .loading
    let items: AsyncStream<[TimelineItem]>
    do {
      items = try await openTimeline()
    } catch {
      if thisStart == startCount { state = .failed("Could not open this chat.") }
      return
    }
    // Keys the NSE stored, or a recovery that just finished, are retried now that the timeline is open.
    await repository.retryDecryption(sessionIds: [])
    let typing = Task { [repository] in
      for await names in await repository.typingMembers() {
        await MainActor.run { withTypingAnimation { self.typingNames = names } }
      }
    }
    defer { typing.cancel() }
    let identities = Task { [repository] in
      for await warnings in await repository.identityWarnings() {
        await MainActor.run {
          withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            self.identityWarnings = warnings
          }
        }
      }
    }
    defer { identities.cancel() }
    // The draft left in this room, here or on another device, comes back in the composer.
    if draft.isEmpty, let saved = await repository.loadDraft() { draft = saved }
    await repository.markAsRead()
    // What decorates the room loads beside the timeline, so the messages show without waiting for it (one of these
    // asks the server).
    let extras = Task { [weak self] in
      guard let self else { return }
      async let pinned: Void = loadPinned()
      async let roomState: Void = loadRoomState()
      async let reactions: Void = loadRecentReactions()
      async let saved: Void = loadSaved()
      async let threadPref: Void = loadThreadPref()
      let commands = await repository.botCommands()
      _ = await (pinned, roomState, reactions, saved, threadPref)
      botCommands = commands
    }
    defer { extras.cancel() }
    for await list in items where thisStart == startCount {
      state = .loaded(list)
      noteStart(in: list)
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

  /// Opens the timeline, trying again a few times when the room is not in the store yet (a notification cold start).
  private func openTimeline() async throws(TimelineError) -> AsyncStream<[TimelineItem]> {
    var lastError: TimelineError = .unavailable
    for attempt in 0...openRetryDelays.count {
      do { return try await repository.open() } catch {
        lastError = error
        let canRetry = error == .roomNotFound || error == .unavailable
        guard canRetry, attempt < openRetryDelays.count else { throw error }
        try? await Task.sleep(for: openRetryDelays[attempt])
      }
    }
    throw lastError
  }

  /// Loads a picture (an avatar) as data; `nil` when it fails.
  public func picture(_ reference: MediaReference) async -> Data? {
    try? await media.thumbnail(reference, width: 96, height: 96)
  }

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

  /// One approach of the top of the timeline loads one page. Leaving the top re-arms the trigger. A call while a page
  /// is already loading, or at the start of the room, does nothing.
  public func topZoneChanged(isNearTop: Bool) async {
    if !isNearTop {
      topArmed = true
      return
    }
    guard topArmed, !isLoadingOlder, !reachedStart, !isHistoryPaused else { return }
    topArmed = false
    await loadOlder()
  }

  /// Loads older pages to fill a timeline that is shorter than the viewport, or that has nothing to show yet, until
  /// the start of the room or the limits of `historyLoading`. A long room is not filled this way: the user scrolls
  /// to the top for each next page (`topZoneChanged`).
  public func loadOlderWhileVisible() async {
    var pages = 0
    var failures = 0
    while !reachedStart, !Task.isCancelled {
      guard pages < historyLoading.maxAutomaticPages, failures < historyLoading.maxFailures else {
        isHistoryPaused = true
        return
      }
      if isLoadingOlder {
        // A page is on its way (the one asked when the chat opened, or a jump): wait for it. Counting it as a page
        // paused a slow room after a few seconds with nothing loaded.
        try? await Task.sleep(for: historyLoading.pause)
        continue
      }
      if await loadOlder() {
        pages += 1
        failures = 0
      } else {
        failures += 1
      }
      try? await Task.sleep(
        for: failures == 0 ? historyLoading.pause : historyLoading.pauseAfterFailure)
    }
  }

  /// What the timeline shows in place of messages while it has none, so the screen is never blank.
  public enum Placeholder: Equatable, Sendable {
    /// Older pages are loading.
    case loading
    /// Loading stopped by itself; the user asks for more.
    case paused
  }

  /// `nil` once a message shows or the start of the room is reached (the empty-chat card takes over there).
  public var placeholder: Placeholder? {
    guard case .loaded = state, !reachedStart else { return nil }
    let hasMessage = rows.contains { row in
      switch row {
      case .message, .album: true
      case .other, .notices: false
      }
    }
    if hasMessage { return nil }
    return isHistoryPaused ? .paused : .loading
  }

  /// The user asked for earlier messages after loading paused: one page, not another automatic run.
  public func resumeHistory() async {
    isHistoryPaused = false
    topArmed = false
    await loadOlder()
  }

  /// Keeps `reachedStart` true to the list on screen. The SDK empties and refills a timeline after a gap in sync; the
  /// refilled list no longer holds the start of the room, and without this the room stayed empty with nothing asking
  /// for older messages.
  private func noteStart(in list: [TimelineItem]) {
    if list.contains(where: { $0.kind == .timelineStart }) {
      reachedStart = true
      sawTimelineStart = true
    } else if sawTimelineStart {
      sawTimelineStart = false
      reachedStart = false
      isHistoryPaused = false
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

  /// Scrolls to the first message sent on `date`'s day or later, loading older pages until the timeline reaches that
  /// day (at most `maxPages`). Works in encrypted chats, since it reads the decrypted timeline.
  public func jump(toDate date: Date, calendar: Calendar = .current, maxPages: Int = 200) async {
    let day = calendar.startOfDay(for: date)
    var pages = 0
    while !reachedStart, pages < maxPages, oldestMessageDate.map({ $0 >= day }) ?? true {
      guard await loadOlder() else { break }
      pages += 1
      try? await Task.sleep(for: .milliseconds(120))
    }
    guard let target = firstMessage(onOrAfter: day), let eventId = target.eventId else {
      showToast("No messages from that day")
      return
    }
    await jump(toEvent: eventId, maxPages: 0)
  }

  /// Scrolls to the room's first message, loading older pages until the start of the room (web: "Jump to start").
  public func jumpToStart() async {
    await jump(toDate: .distantPast)
  }

  /// The date of the oldest loaded message.
  var oldestMessageDate: Date? {
    guard case .loaded(let items) = state else { return nil }
    return items.lazy.compactMap { item -> Date? in
      if case .message(let message) = item.kind { message.date } else { nil }
    }.first
  }

  /// The first loaded message sent at or after `day`.
  func firstMessage(onOrAfter day: Date) -> TimelineMessage? {
    guard case .loaded(let items) = state else { return nil }
    for item in items {
      if case .message(let message) = item.kind, message.date >= day, message.eventId != nil {
        return message
      }
    }
    return nil
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

  /// Sends again the message that failed to send.
  public func retry(_ message: TimelineMessage) async {
    guard message.sendState == .failed, let transactionId = message.transactionId else { return }
    await repository.retrySend(transactionId: transactionId)
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

  /// Picking messages to copy, forward or delete together (Flutter selection mode).
  public private(set) var isSelectingMessages = false
  /// The picked messages, by event id.
  public private(set) var selectedMessages: [String: TimelineMessage] = [:]

  public func startSelecting(_ message: TimelineMessage) {
    guard let eventId = message.eventId else { return }
    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
      composerMode = .new
      selectedMessages = [eventId: message]
      isSelectingMessages = true
    }
  }

  public func toggleSelection(_ message: TimelineMessage) {
    guard let eventId = message.eventId else { return }
    if selectedMessages.removeValue(forKey: eventId) == nil { selectedMessages[eventId] = message }
  }

  public func isSelected(_ message: TimelineMessage) -> Bool {
    message.eventId.map { selectedMessages[$0] != nil } ?? false
  }

  public func endSelecting() {
    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
      isSelectingMessages = false
      selectedMessages = [:]
    }
  }

  /// The picked messages, oldest first.
  public var orderedSelection: [TimelineMessage] {
    selectedMessages.values.sorted { $0.date < $1.date }
  }

  /// Every picked message may be deleted by the user.
  public var canDeleteSelection: Bool {
    !selectedMessages.isEmpty && selectedMessages.values.allSatisfy(canDelete)
  }

  /// The text of the picked messages, oldest first, each with its sender, as Telegram copies several messages.
  public var selectionText: String {
    orderedSelection.compactMap { message in
      Self.text(of: message.body).map { "\(message.senderName): \($0)" }
    }.joined(separator: "\n")
  }

  public func copySelection() {
    UIPasteboard.general.string = selectionText
    showToast(selectedMessages.count == 1 ? "Copied" : "Copied \(selectedMessages.count) messages")
    endSelecting()
  }

  public func deleteSelection() async {
    guard canDeleteSelection else { return }
    let messages = orderedSelection
    endSelecting()
    for message in messages { await delete(message) }
  }

  /// Forwards several messages to one room, oldest first.
  public func forward(_ messages: [TimelineMessage], to room: RoomSummary) async {
    var failed = false
    for message in messages {
      guard let eventId = message.eventId else { continue }
      do { try await repository.forward(eventId: eventId, to: room.id) } catch { failed = true }
    }
    endSelecting()
    if failed {
      errorMessage = "Could not forward every message."
    } else {
      showToast("Forwarded to \(room.name)")
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
  public var typingText: String? { TypingText.line(for: typingNames) }

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
      errorMessage = Self.attachmentFailureMessage(error)
    }
  }

  /// Why an attachment was not sent, as the composer shows it.
  static func attachmentFailureMessage(_ error: TimelineError) -> String {
    switch error {
    case .tooLarge: "This file is larger than the server allows."
    case .unsupportedType: "This type of file cannot be sent."
    case .network: "Could not reach the server. Check your connection and try again."
    case .forbidden: "You are not allowed to send files in this chat."
    case .uploadFailed: "Could not upload the file. Please try again."
    case .notSignedIn, .roomNotFound, .unavailable, .requestFailed:
      "Could not send the attachment. Please try again."
    }
  }

  /// Sends what the preview kept, one after another (pictures sent together show as an album), the caption with the
  /// last one, as the Flutter upload manager does. The composer's draft, which the preview offered as the caption, is
  /// cleared; the copied files are deleted once sent.
  func send(batch: [AttachmentLoader.Loaded], caption: String) async {
    let caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
    draft = ""
    let limit = await media.maxUploadSize()
    let tooLarge = batch.filter { item in limit.map { (item.size ?? 0) > $0 } ?? false }
    for item in tooLarge { AttachmentLoader.remove(item) }
    let batch = batch.filter { item in !tooLarge.contains { $0.id == item.id } }
    var limitMessage: String?
    if let limit, !tooLarge.isEmpty {
      let size = Self.sizeText(limit) ?? "\(limit) bytes"
      limitMessage =
        tooLarge.count == 1
        ? "This file is larger than the server allows (\(size))."
        : "\(tooLarge.count) files are larger than the server allows (\(size))."
    }
    for (index, item) in batch.enumerated() {
      let isLast = index == batch.count - 1
      await send(
        attachment: item.kind, fileURL: item.fileURL, mimeType: item.mimeType, size: item.size,
        caption: isLast && !caption.isEmpty ? caption : nil)
      AttachmentLoader.remove(item)
    }
    if let limitMessage { errorMessage = limitMessage }
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

  /// The members whose name or Matrix id contains the mention query, at most six. Someone who may notify the room
  /// is also offered « Notify everyone » (`@room`).
  public var mentionSuggestions: [RoomMember] {
    guard let query = mentionQuery?.lowercased() else { return [] }
    let found = members.filter { member in
      query.isEmpty || member.name.lowercased().contains(query)
        || member.id.lowercased().contains(query)
    }
    guard canNotifyRoom else { return Array(found.prefix(6)) }
    if RoomMember.offersEveryoneFirst(for: query) { return [.everyone] + found.prefix(5) }
    return query.isEmpty ? Array(found.prefix(5)) + [.everyone] : Array(found.prefix(6))
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
    // « @room » stays as text: the data layer reads it there, it is no link to a person.
    if member != .everyone, !mentions.contains(member) { mentions.append(member) }
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
    let mode = composerMode
    // A new message that starts with « / » is a bot's command, a client command (`/me`, `/shrug`), or a mistake
    // that is not sent, as on the web.
    var prepared = ComposerCommand.message(typed)
    if case .new = mode, BotCommand.command(for: typed, in: botCommands) == nil {
      prepared = ComposerCommand.prepare(typed)
    }
    if case .unknown = prepared {
      errorMessage =
        "This command does not exist. Start with “//” to send a text that starts with “/”."
      return
    }
    let picked = mentions
    mentions = []
    sendCount += 1
    draft = ""
    await repository.setTyping(false)
    composerMode = .new
    errorMessage = nil
    do {
      switch mode {
      case .new:
        if let command = BotCommand.command(for: typed, in: botCommands) {
          try await repository.send(command: command, text: typed)
        } else if case .emote(let action) = prepared {
          try await repository.send(emote: Self.applyingMentions(picked, to: action))
        } else if case .message(let body) = prepared {
          try await repository.send(text: Self.applyingMentions(picked, to: body))
        }
      case .reply(let eventId, _):
        try await repository.reply(text: Self.applyingMentions(picked, to: typed), to: eventId)
      case .edit(let eventId):
        try await repository.edit(eventId: eventId, text: Self.applyingMentions(picked, to: typed))
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
      if message.senderId == directUserId {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
          blockedUserId = message.senderId
        }
      }
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

  /// What the room's details decide about the screen: moderator rights, a successor room, a blocked person.
  func loadRoomState() async {
    guard let detailsRepository,
      let details = try? await detailsRepository.details(roomId: roomId)
    else { return }
    canRedactOthers = details.canRedactOthers
    canSendMessages = details.canSendMessages
    directUserId = details.directUserId
    isEncrypted = details.isEncrypted
    canNotifyRoom = details.canNotifyRoom
    isDirect = details.isDirect
    isBroadcast = details.isBroadcast
    memberCount = details.isDirect ? nil : details.joinedMemberCount
    // A notification may have opened this screen with a placeholder name ("Chat" / the alert title).
    if !details.name.isEmpty { roomName = details.name }
    if let avatar = details.avatar { roomAvatar = avatar }
    var blocked: String?
    if let userId = details.directUserId, let blocking, await blocking.isBlocked(userId) {
      blocked = userId
    }
    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
      successorRoomId = details.successorRoomId
      blockedUserId = blocked
    }
  }

  /// The other person's presence in a direct chat, under the name in the header; `nil` elsewhere or when unknown.
  public private(set) var presenceLine: String?

  /// The user may notify everyone in the room, so the mention list offers `@room`.
  public private(set) var canNotifyRoom = false

  /// A direct chat and a Broadcast each have their own empty-chat card.
  private var isDirect = false
  private var isBroadcast = false

  /// What the timeline shows while the room has no message.
  public var emptyChatCard: EmptyChatCard {
    .card(
      roomName: roomName, isDirect: isDirect, isBroadcast: isBroadcast, isEncrypted: isEncrypted,
      canPost: canSendMessages)
  }

  /// The room is encrypted: the header shows a lock beside the name, as the Flutter app does.
  public private(set) var isEncrypted = false

  /// How many people are in a group; `nil` in a direct chat or before the room's details load.
  public private(set) var memberCount: Int?

  /// The line under the name in the header: the other person's presence in a direct chat, the number of members in
  /// a group, as the Flutter and web headers show.
  public var headerSubtitle: String? {
    if let presenceLine { return presenceLine }
    guard let memberCount, memberCount > 0 else { return nil }
    return memberCount == 1 ? "1 member" : "\(memberCount) members"
  }

  /// Asks the open timeline to decrypt events that were UTD, for example after keys arrive from the NSE or after
  /// recovery. An empty session list retries every such event, as Element X does.
  public func retryDecryption() async {
    await repository.retryDecryption(sessionIds: [])
  }

  /// Reads the other person's presence now and every `interval` while the chat shows in the foreground, as the web
  /// reads the presence of the people shown (D80). The room screen cancels this task when the scene is not active,
  /// so a DM left in the background does not keep polling. It also ends when the task is cancelled.
  public func watchPresence(every interval: Duration = .seconds(15)) async {
    guard threadRootId == nil, let detailsRepository else { return }
    // The room's details load with the timeline: wait a few seconds for them to say whether this is a direct chat.
    var waits = 0
    while !Task.isCancelled {
      guard let userId = directUserId else {
        waits += 1
        guard waits <= 10 else { return }
        try? await Task.sleep(for: .seconds(1))
        continue
      }
      let line = await detailsRepository.presence(of: userId)?.line
      if line != presenceLine {
        withAnimation(.easeInOut(duration: 0.25)) { presenceLine = line }
      }
      try? await Task.sleep(for: interval)
    }
  }

  /// The link that opens the room that replaced this one.
  public var successorLink: URL? {
    successorRoomId.flatMap {
      let via =
        MatrixLink.server(of: $0).map { [$0] } ?? MatrixLink.server(of: roomId).map { [$0] } ?? []
      return MatrixLink.room(idOrAlias: $0, eventId: nil, via: via).url
    }
  }

  /// Unblocks the other person of this direct chat; the composer comes back.
  public func unblock() async {
    guard let userId = blockedUserId, let blocking else { return }
    if await blocking.unblock(userId) {
      withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { blockedUserId = nil }
    } else {
      errorMessage = "Could not unblock. Please try again."
    }
  }

  /// Sends the poll the user wrote; `false` (with a message) when it failed, so the sheet stays open.
  @discardableResult
  public func createPoll(_ draft: PollDraft) async -> Bool {
    guard draft.canSend else { return false }
    errorMessage = nil
    do {
      try await repository.createPoll(draft)
      sendCount += 1
      return true
    } catch {
      errorMessage = "Could not send the poll."
      return false
    }
  }

  /// Votes for `answerId` in a poll that has not ended, or takes the vote back in a multiple-choice poll.
  public func vote(_ answerId: String, in message: TimelineMessage) async {
    guard let poll = message.poll, !poll.isEnded, let eventId = message.eventId else { return }
    do {
      try await repository.vote(poll.selection(tapping: answerId), in: eventId)
    } catch {
      errorMessage = "Could not send your vote."
    }
  }

  /// The user may end this poll: they created it and it is still open.
  public func canEndPoll(_ message: TimelineMessage) -> Bool {
    message.isOwn && message.eventId != nil && message.poll.map { !$0.isEnded } == true
  }

  public func endPoll(_ message: TimelineMessage) async {
    guard canEndPoll(message), let eventId = message.eventId else { return }
    do {
      try await repository.endPoll(eventId)
    } catch {
      errorMessage = "Could not end the poll."
    }
  }

  /// The user may delete this message: their own, or anyone's as a moderator. Their own message that is not sent
  /// yet (still sending, or failed) is discarded instead, so it never leaves the device.
  public func canDelete(_ message: TimelineMessage) -> Bool {
    if message.eventId == nil { return message.isOwn && message.transactionId != nil }
    guard message.body != .redacted else { return false }
    return message.isOwn || canRedactOthers
  }

  /// The `matrix.to` link to the message, to share it outside the app; `nil` before it is sent.
  public func link(to message: TimelineMessage) -> URL? {
    guard let eventId = message.eventId else { return nil }
    let via = MatrixLink.server(of: message.senderId).map { [$0] } ?? []
    return MatrixLink.room(idOrAlias: roomId, eventId: eventId, via: via).url
  }

  /// Copies the message's link and confirms it.
  public func copyLink(to message: TimelineMessage) {
    guard let url = link(to: message) else { return }
    UIPasteboard.general.url = url
    showToast("Link copied")
  }

  public func delete(_ message: TimelineMessage) async {
    guard canDelete(message) else { return }
    do {
      if let eventId = message.eventId {
        try await repository.redact(eventId: eventId)
      } else if let transactionId = message.transactionId {
        try await repository.discardUnsent(transactionId: transactionId)
      }
    } catch {
      errorMessage = "Could not delete the message."
    }
  }

  public func toggleReaction(_ key: String, on message: TimelineMessage) async {
    guard let eventId = message.eventId else { return }
    let adds = !message.reactions.contains { $0.key == key && $0.includesOwn }
    do {
      try await repository.toggleReaction(key, on: eventId)
      if adds {
        reactionBar = Self.reactionBar(recents: [key] + reactionBar)
        await repository.addRecentReaction(key)
      }
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

  /// Downloads the messages' pictures, videos or files (every picture of an album) for the share sheet, as the Flutter
  /// message menu's Share and Save do. They download together and keep the album's order. Nothing is offered if one
  /// download fails; the error says so.
  func share(_ messages: [TimelineMessage]) async {
    guard !messages.isEmpty, !isPreparingShare else { return }
    isPreparingShare = true
    defer { isPreparingShare = false }
    let found = await withTaskGroup(of: (Int, URL?).self) { group in
      for (index, message) in messages.enumerated() {
        group.addTask { (index, await self.file(of: message)) }
      }
      var urls = [URL?](repeating: nil, count: messages.count)
      for await (index, url) in group { urls[index] = url }
      return urls
    }
    let urls = found.compactMap { $0 }
    if urls.count == messages.count { sharedFiles = DownloadedFiles(urls: urls) }
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
    case .text(let text), .emote(let text), .notice(let text), .location(let text, _): text
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
