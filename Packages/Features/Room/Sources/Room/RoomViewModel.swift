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
  public internal(set) var mentions: [RoomMember] = []
  /// The room's members, loaded the first time the user types "@".
  public internal(set) var members: [RoomMember] = []
  @ObservationIgnored var didLoadMembers = false
  public internal(set) var composerMode: ComposerMode = .new
  public internal(set) var isLoadingOlder = false
  public internal(set) var reachedStart = false
  /// How far the timeline loads older pages by itself.
  public var historyLoading = HistoryLoading()
  /// The top of the timeline must leave the viewport before another page can be asked for (one trigger, one page).
  var topArmed = true
  /// Loading by itself stopped (`HistoryLoading`): the top of the timeline offers "Load earlier messages".
  public internal(set) var isHistoryPaused = false
  /// A list of this timeline held the start of the room; a later list without it means the SDK reset the timeline.
  @ObservationIgnored var sawTimelineStart = false
  public internal(set) var errorMessage: String?
  /// The other members typing now, by name.
  public private(set) var typingNames: [String] = []
  /// How many attachments are uploading.
  public internal(set) var uploadCount = 0
  /// The room's pinned messages, oldest pin first, and the one the banner shows.
  public internal(set) var pinned: [TimelineMessage] = []
  public internal(set) var pinnedIndex = 0
  /// The user may delete other people's messages, as a moderator; loaded with the timeline.
  public private(set) var canRedactOthers = false
  @ObservationIgnored let saved: (any SavedMessagesRepository)?
  @ObservationIgnored let threadPrefs: (any ThreadPrefsRepository)?
  /// On a thread's screen: what the user chose for it, shared with the web app; `nil` when nothing was chosen.
  var threadPref: ThreadPref?
  /// The commands of the room's bots, loaded with the timeline.
  public private(set) var botCommands: [BotCommand] = []
  @ObservationIgnored let gifs: (any GifRepository)?
  public internal(set) var gifsAvailable = false
  public internal(set) var stickerPacks: [StickerPack] = []

  /// The message whose edit history the sheet shows.
  public var historyMessage: TimelineMessage?
  /// The message whose details the info sheet shows (Flutter `EventInfoDialog`).
  public var infoMessage: TimelineMessage?
  /// The files a message menu's Share downloaded; the share sheet also saves them to Photos or Files.
  var sharedFiles: DownloadedFiles?
  /// Share is downloading; the screen shows a spinner until the sheet opens.
  var isPreparingShare = false

  /// The event ids of this room's messages the user saved.
  public internal(set) var savedEventIds: Set<String> = []

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
  public internal(set) var blockedUserId: String?
  /// The user may post in this room; in a Broadcast only moderators do, and the composer gives way to a note.
  public private(set) var canSendMessages = true

  /// The other person of this direct chat, when it has one.
  @ObservationIgnored var directUserId: String?
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
  @ObservationIgnored let detailsRepository: (any RoomDetailsRepository)?
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
  public internal(set) var reactionBar: [String] = RoomViewModel.quickReactions

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
    threadPrefs: (any ThreadPrefsRepository)? = nil,
    scrollMemory: TimelineScrollMemory? = nil,
    gifs: (any GifRepository)? = nil
  ) {
    self.gifs = gifs
    self.scrollMemory = scrollMemory
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
      saved: saved, threadTimeline: nil, threadRootId: eventId, threadPrefs: threadPrefs,
      gifs: gifs)
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
      async let gifs: Void = loadGifsAvailability()
      async let stickers: Void = loadStickerPacks()
      let commands = await repository.botCommands()
      _ = await (pinned, roomState, reactions, saved, threadPref, gifs, stickers)
      botCommands = commands
    }
    defer { extras.cancel() }
    for await list in items where thisStart == startCount {
      state = .loaded(list)
      noteStart(in: list)
      restoreScroll(in: list)
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

  /// The rows the screen draws: messages grouped by sender, pictures sent together as albums, without the room events
  /// the chat settings hide.
  public var rows: [ChatRow] {
    guard case .loaded(let items) = state else { return [] }
    return TimelineRows.rows(from: display().visible(items))
  }

  /// Counts sent messages, so the send button and haptics react to each send.
  public internal(set) var sendCount = 0

  /// The message the timeline scrolls to (a replied-to message, a pin), then clears.
  var scrollTarget: String?
  /// The row put back at the top of the screen when the chat reopens where it was left, then clears.
  var restoreTarget: String?
  /// Where this room's chats were left; `nil` for a thread, which always opens on its newest message.
  @ObservationIgnored let scrollMemory: TimelineScrollMemory?
  /// The saved position is applied once, to the first messages that show.
  @ObservationIgnored var didRestoreScroll = false
  /// The row that briefly flashes after a jump, so the eye finds it.
  public internal(set) var highlightedEventId: String?
  /// The sheet listing who reacted to, or has seen, a message.
  var peopleSheet: PeopleSheet?

  /// What the people sheet lists.
  struct PeopleSheet: Identifiable {
    let title: String
    let userIds: [String]
    var id: String { title + userIds.joined() }
  }

  /// Picking messages to copy, forward or delete together (Flutter selection mode).
  public internal(set) var isSelectingMessages = false
  /// The picked messages, by event id.
  public internal(set) var selectedMessages: [String: TimelineMessage] = [:]

  func showToast(_ text: String) {
    toast = text
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(2))
      if self?.toast == text { self?.toast = nil }
    }
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
