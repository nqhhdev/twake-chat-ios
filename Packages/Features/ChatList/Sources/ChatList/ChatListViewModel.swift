import Domain
import Foundation
import Observation
import SwiftUI

/// The chat list: the joined rooms, as the repository orders them (most recent activity first), kept up to date, and
/// the Log out action. Logging out is the app's job: the coordinator passes it in, so this feature does not know the
/// authentication feature (ADR 0005).
@MainActor @Observable
public final class ChatListViewModel {
  public enum State: Equatable {
    case loading
    case loaded([RoomSummary])
    /// Signed in, but the room list has no joined room.
    case empty
    /// The room list could not be started.
    case failed(String)
  }

  public private(set) var state: State = .loading
  /// The search field's text; it filters the rooms by name.
  public var query = ""
  /// Which chats the list shows, as the filter chips under the search field choose.
  public var filter = Filter.all
  /// The chats picked in select mode.
  public var selection = Set<String>()

  public enum Filter: String, CaseIterable, Identifiable, Sendable {
    case all, unread, favourites, people, groups, broadcasts
    public var id: Self { self }
    public var title: String {
      switch self {
      case .all: "All"
      case .unread: "Unread"
      case .favourites: "Favourites"
      case .people: "People"
      case .groups: "Groups"
      case .broadcasts: "Broadcasts"
      }
    }

    func includes(_ room: RoomSummary) -> Bool {
      switch self {
      case .all: true
      case .unread: room.isUnread || room.mentionCount > 0
      case .favourites: room.isFavourite
      case .people: room.isDirect
      case .groups: !room.isDirect
      case .broadcasts: room.isBroadcast
      }
    }
  }
  public private(set) var isLoggingOut = false
  /// Shown when logout failed and the session is still saved on this device.
  public private(set) var logOutErrorMessage: String?

  @ObservationIgnored private let repository: any RoomListRepository
  @ObservationIgnored private let logOutAction: @MainActor () async -> Bool
  /// Loads room pictures; `nil` shows initials only.
  @ObservationIgnored public let media: (any MediaRepository)?
  /// The invitations being accepted or declined.
  public private(set) var answering: Set<String> = []
  /// Why the last accept or decline failed.
  public private(set) var inviteErrorMessage: String?
  /// Counts `start()` calls, so an earlier call whose stream a later one ended does not stop the later one.
  @ObservationIgnored private var startCount = 0

  /// - Parameter logOut: Signs out and returns `true`, or returns `false` when the session is still saved and the user
  ///   should try again.
  /// The chats the user left; `nil` hides "Archived chats".
  @ObservationIgnored private let archive: (any ArchivedRoomsRepository)?
  /// The homeserver's public groups; `nil` hides "Public groups".
  @ObservationIgnored private let publicRooms: (any PublicRoomsRepository)?
  /// What spaces hold; `nil` opens a space as a plain room.
  @ObservationIgnored private let spaces: (any SpacesRepository)?

  public init(
    repository: any RoomListRepository, media: (any MediaRepository)? = nil,
    archive: (any ArchivedRoomsRepository)? = nil,
    publicRooms: (any PublicRoomsRepository)? = nil,
    spaces: (any SpacesRepository)? = nil,
    messageSearch: (any RoomSearchRepository)? = nil,
    doNotDisturb: DoNotDisturb? = nil,
    saved: (any SavedMessagesRepository)? = nil,
    threadPrefs: (any ThreadPrefsRepository)? = nil,
    people: (any PeopleRepository)? = nil,
    openPerson: (@MainActor (String) async -> Bool)? = nil,
    previewTimeline: (@MainActor (String) -> any TimelineRepository)? = nil,
    logOut: @escaping @MainActor () async -> Bool
  ) {
    self.previewTimeline = previewTimeline
    self.people = people
    self.openPerson = openPerson
    self.saved = saved
    self.threadPrefs = threadPrefs
    self.doNotDisturb = doNotDisturb
    self.messageSearch = messageSearch
    self.spaces = spaces
    self.archive = archive
    self.publicRooms = publicRooms
    self.repository = repository
    self.media = media
    self.logOutAction = logOut
  }

  @ObservationIgnored private let messageSearch: (any RoomSearchRepository)?
  @ObservationIgnored let saved: (any SavedMessagesRepository)?
  @ObservationIgnored let threadPrefs: (any ThreadPrefsRepository)?
  /// The threads the user follows by choice, for the Activity (`Activity.swift`).
  public internal(set) var followedThreads: [FollowedThread] = []
  @ObservationIgnored private let people: (any PeopleRepository)?
  @ObservationIgnored private let openPerson: (@MainActor (String) async -> Bool)?
  /// The people the search text finds (the user directory and ToM contacts), for the global search.
  public private(set) var peopleResults: [Person] = []

  /// Opens the direct chat with someone the search found, creating it when needed.
  public func open(_ person: Person) async {
    guard let openPerson else { return }
    if await !openPerson(person.id) { actionErrorMessage = "Could not open the chat." }
  }

  /// Reading and turning off the account's do not disturb, given by the app from the account settings.
  public struct DoNotDisturb: Sendable {
    public let isOn: @Sendable () async -> Bool
    public let turnOff: @Sendable () async -> Bool

    public init(
      isOn: @escaping @Sendable () async -> Bool, turnOff: @escaping @Sendable () async -> Bool
    ) {
      self.isOn = isOn
      self.turnOff = turnOff
    }
  }
  @ObservationIgnored private let doNotDisturb: DoNotDisturb?
  /// Do not disturb is on: the list shows a banner to turn it off.
  public private(set) var isDoNotDisturbOn = false

  public func refreshDoNotDisturb() async {
    guard let doNotDisturb else { return }
    let on = await doNotDisturb.isOn()
    guard on != isDoNotDisturbOn else { return }
    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { isDoNotDisturbOn = on }
  }

  public func turnOffDoNotDisturb() async {
    guard let doNotDisturb else { return }
    if await doNotDisturb.turnOff() {
      withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { isDoNotDisturbOn = false }
    } else {
      actionErrorMessage = "Could not turn off Do Not Disturb."
    }
  }
  /// The messages the server found for the search text, in rooms the list knows.
  public private(set) var messageResults: [RoomSearchResult] = []
  public private(set) var isSearchingMessages = false

  /// Searches the server's messages for the search text, after a short pause in typing (the caller's task is
  /// cancelled by the next keystroke). Encrypted messages are not on the server's index.
  public func searchMessages() async {
    let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard term.count >= 2 else {
      messageResults = []
      peopleResults = []
      return
    }
    guard let messageSearch else {
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled else { return }
      let persons = await searchPeople(term)
      guard !Task.isCancelled else { return }
      withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { peopleResults = persons }
      return
    }
    try? await Task.sleep(for: .milliseconds(400))
    guard !Task.isCancelled else { return }
    isSearchingMessages = true
    defer { isSearchingMessages = false }
    async let found = searchPeople(term)
    let page = try? await messageSearch.searchEverywhere(term, from: nil)
    let persons = await found
    guard !Task.isCancelled, term == query.trimmingCharacters(in: .whitespacesAndNewlines) else {
      return
    }
    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { peopleResults = persons }
    let known = Set(allJoinedRooms.map(\.id))
    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
      messageResults = (page?.results ?? []).filter { $0.roomId.map(known.contains) ?? false }
    }
  }

  /// At most five people, leaving out those already shown as a direct chat in the list.
  private func searchPeople(_ term: String) async -> [Person] {
    guard let people, let found = try? await people.search(term) else { return [] }
    let shown = Set(visibleRooms.filter(\.isDirect).map(\.name))
    return Array(found.filter { !shown.contains($0.name) }.prefix(5))
  }

  /// Every loaded room the user is in, whatever the search text and filter: what the app icon badge counts.
  public var allJoinedRooms: [RoomSummary] {
    guard case .loaded(let rooms) = state else { return [] }
    return rooms.filter { !$0.isInvite }
  }

  /// The room a message result belongs to.
  public func room(of result: RoomSearchResult) -> RoomSummary? {
    allJoinedRooms.first { $0.id == result.roomId }
  }

  /// Whether the list offers "Archived chats".
  public var hasArchive: Bool { archive != nil }

  /// The page of a space; a room picked there opens through `onOpen`. `nil` when the app gave no spaces.
  public func makeSpace(
    _ space: RoomSummary, onOpen: @escaping @MainActor (RoomSummary) -> Void
  ) -> SpaceViewModel? {
    guard let spaces, space.isSpace else { return nil }
    return SpaceViewModel(
      space: space, repository: spaces,
      picture: { @Sendable [weak self] reference in await self?.picture(reference) },
      onOpen: onOpen,
      markRead: { [repository] roomId in try? await repository.setUnread(false, roomId: roomId) })
  }

  /// The timeline of a room by its id, for the long-press preview; `nil` shows the menu without a preview.
  @ObservationIgnored private let previewTimeline: (@MainActor (String) -> any TimelineRepository)?

  /// Whether a long press on `room` shows its latest messages above the menu. Spaces and invitations keep the plain menu.
  public func hasPreview(_ room: RoomSummary) -> Bool {
    previewTimeline != nil && !room.isSpace && !room.isInvite
  }

  /// The preview's model on a new timeline of `room`, or `nil` when `hasPreview(room)` is false.
  public func makePreview(_ room: RoomSummary) -> ChatPreviewViewModel? {
    guard hasPreview(room), let previewTimeline else { return nil }
    return ChatPreviewViewModel(room: room, repository: previewTimeline(room.id))
  }

  /// The public groups screen's model; joining a group opens it through `onJoined`.
  public func makePublicRooms(
    onJoined: @escaping @MainActor (RoomSummary) -> Void
  ) -> PublicRoomsViewModel? {
    publicRooms.map { PublicRoomsViewModel(repository: $0, onJoined: onJoined) }
  }

  /// The archive screen's model.
  public func makeArchive() -> ArchivedChatsViewModel? {
    archive.map(ArchivedChatsViewModel.init(repository:))
  }

  /// Joins the invited room (`accept`) or refuses it; the room list then shows the room joined, or drops it.
  public func answerInvite(_ room: RoomSummary, accept: Bool) async {
    guard !answering.contains(room.id) else { return }
    answering.insert(room.id)
    defer { answering.remove(room.id) }
    inviteErrorMessage = nil
    do {
      if accept {
        try await repository.accept(roomId: room.id)
      } else {
        try await repository.decline(roomId: room.id)
      }
    } catch {
      inviteErrorMessage = accept ? "Could not join the room." : "Could not decline the invitation."
    }
  }

  /// Loads a room's picture as data, for the avatar.
  public func picture(_ reference: MediaReference) async -> Data? {
    try? await media?.thumbnail(reference, width: 112, height: 112)
  }

  /// Starts the room list and follows its updates until the calling task is cancelled (the screen goes away) or the
  /// repository stops; the room list is then stopped, unless a later `start()` has begun meanwhile: starting again ends
  /// the earlier stream, and stopping then would end the later one too.
  public func start() async {
    startCount += 1
    let thisStart = startCount
    state = .loading
    let rooms: AsyncStream<[RoomSummary]>
    do {
      rooms = try await repository.start()
    } catch {
      if thisStart == startCount { state = .failed("Could not load your rooms.") }
      return
    }
    for await list in rooms where thisStart == startCount {
      state = list.isEmpty ? .empty : .loaded(list)
    }
    if thisStart == startCount { await repository.stop() }
  }

  public func logOut() async {
    guard !isLoggingOut else { return }
    isLoggingOut = true
    defer { isLoggingOut = false }
    logOutErrorMessage = nil
    if await !logOutAction() {
      logOutErrorMessage = "Could not log out. Please try again."
    }
  }

  /// The loaded rooms whose name contains the search text, all of them when it is empty.
  /// The invitations among the visible rooms; the list groups them in their own section.
  public var invites: [RoomSummary] { visibleRooms.filter(\.isInvite) }

  /// The joined rooms among the visible rooms.
  public var joinedRooms: [RoomSummary] {
    visibleRooms.filter { !$0.isInvite && filter.includes($0) }
  }

  /// The joined favourites, shown first.
  public var favouriteRooms: [RoomSummary] { joinedRooms.filter(\.isFavourite) }

  /// The joined rooms that are neither favourites nor low priority.
  public var otherRooms: [RoomSummary] {
    joinedRooms.filter { !$0.isFavourite && !$0.isLowPriority }
  }

  /// The joined rooms put in low priority, shown last (a favourite stays with the favourites).
  public var lowPriorityRooms: [RoomSummary] {
    joinedRooms.filter { $0.isLowPriority && !$0.isFavourite }
  }

  /// Puts a room in low priority, or takes it out.
  public func setLowPriority(_ lowPriority: Bool, room: RoomSummary) async {
    await act("Could not update the chat.") { [repository] () async throws(RoomListError) in
      try await repository.setLowPriority(lowPriority, roomId: room.id)
    }
  }

  /// Why the last swipe action failed.
  public private(set) var actionErrorMessage: String?

  /// Marks a room as unread, or as read.
  public func setUnread(_ unread: Bool, room: RoomSummary) async {
    await act("Could not update the chat.") { [repository] () async throws(RoomListError) in
      try await repository.setUnread(unread, roomId: room.id)
    }
  }

  /// Adds a room to the favourites, or takes it out.
  public func setFavourite(_ favourite: Bool, room: RoomSummary) async {
    await act("Could not update the favourites.") { [repository] () async throws(RoomListError) in
      try await repository.setFavourite(favourite, roomId: room.id)
    }
  }

  /// Mutes a room, or goes back to the default notifications.
  public func setMuted(_ muted: Bool, room: RoomSummary) async {
    await act("Could not change the notifications.") {
      [repository] () async throws(RoomListError) in
      try await repository.setMuted(muted, roomId: room.id)
    }
  }

  /// The picked chats.
  public var selectedRooms: [RoomSummary] { joinedRooms.filter { selection.contains($0.id) } }

  /// Marks every picked chat read, then ends select mode.
  public func markSelectionRead() async {
    for room in selectedRooms { await setUnread(false, room: room) }
    selection = []
  }

  /// Mutes every picked chat, or unmutes them all when all are muted already.
  public func toggleSelectionMuted() async {
    let rooms = selectedRooms
    let mute = !rooms.allSatisfy(\.isMuted)
    for room in rooms { await setMuted(mute, room: room) }
    selection = []
  }

  /// Adds every picked chat to the favourites, or takes them out when all are favourites already.
  public func toggleSelectionFavourite() async {
    let rooms = selectedRooms
    let favourite = !rooms.allSatisfy(\.isFavourite)
    for room in rooms { await setFavourite(favourite, room: room) }
    selection = []
  }

  /// Leaves every picked chat, then ends select mode.
  public func leaveSelection() async {
    for room in selectedRooms { await leave(room) }
    selection = []
  }

  /// Leaves a room.
  public func leave(_ room: RoomSummary) async {
    await act("Could not leave the chat.") { [repository] () async throws(RoomListError) in
      try await repository.leave(roomId: room.id)
    }
  }

  private func act(
    _ failure: String, _ action: () async throws(RoomListError) -> Void
  ) async {
    actionErrorMessage = nil
    do { try await action() } catch { actionErrorMessage = failure }
  }

  public var visibleRooms: [RoomSummary] {
    guard case .loaded(let rooms) = state else { return [] }
    let text = query.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return rooms }
    return rooms.filter { $0.name.localizedCaseInsensitiveContains(text) }
  }

  /// Every loaded room, ignoring the list's search and filter, so a notification can find its room.
  public var loadedRooms: [RoomSummary] {
    switch state {
    case .loaded(let rooms): rooms
    default: []
    }
  }

  /// The room `roomId` once it appears in the loaded list, or `nil` if it is still unknown after `limit`.
  public func summary(for roomId: String, waitingUpTo limit: Duration = .seconds(10)) async
    -> RoomSummary?
  {
    if let found = loadedRooms.first(where: { $0.id == roomId }) { return found }
    let deadline = ContinuousClock.now + limit
    while ContinuousClock.now < deadline {
      if Task.isCancelled { return nil }
      if let found = loadedRooms.first(where: { $0.id == roomId }) { return found }
      try? await Task.sleep(for: .milliseconds(50))
    }
    return loadedRooms.first(where: { $0.id == roomId })
  }

  /// The row's preview: "sender: text", or the text alone when the sender is unknown; `nil` without a text message.
  public static func preview(of room: RoomSummary) -> String? {
    guard let body = body(of: room) else { return nil }
    // An emote reads as a sentence: "Alice waves" (web `roomRowText.ts`).
    if room.lastMessageKind == .emote {
      let name = room.isLastMessageOwn ? "You" : room.lastMessageSender
      return name.map { "\($0) \(body)" } ?? body
    }
    // "You:" on the user's own message; no name in a direct chat, where only one person writes to the user.
    if room.isLastMessageOwn { return "You: \(body)" }
    guard !room.isDirect, let sender = room.lastMessageSender else { return body }
    return "\(sender): \(body)"
  }

  /// Who types in the room, in place of its last message: "typing…" in a direct chat, where only one person can, and
  /// the names in a group.
  public static func typingLine(of room: RoomSummary) -> String? {
    guard !room.typingNames.isEmpty else { return nil }
    return room.isDirect ? "typing…" : TypingText.line(for: room.typingNames)
  }

  /// The last message as the row names it: its text, or what it is when it has none to show (a picture without a
  /// caption, a voice message, a poll, a deleted or undecryptable message), as the Flutter and web chat lists do.
  static func body(of room: RoomSummary) -> String? {
    let text = room.lastMessageText
    return switch room.lastMessageKind {
    case nil, .text, .emote, .notice: text
    case .picture: text ?? "Photo"
    case .video: text ?? "Video"
    case .audio: "Audio"
    case .voice: "Voice message"
    case .file: text ?? "File"
    case .location: "Location"
    case .sticker: "Sticker"
    case .poll: text.map { "Poll: \($0)" } ?? "Poll"
    case .deleted: "Message deleted"
    case .encrypted: "Encrypted message"
    }
  }

  /// The time beside a room, as the Flutter chat list writes it (`localizedTimeShort`): the hour today, the weekday
  /// this week, the day and month this year, the full date before.
  public static func timeText(_ date: Date, now: Date = .now, calendar: Calendar = .current)
    -> String
  {
    var style = Date.FormatStyle.dateTime
    style.calendar = calendar
    style.timeZone = calendar.timeZone
    style.locale = calendar.locale ?? .autoupdatingCurrent
    if calendar.isDate(date, inSameDayAs: now) { return date.formatted(style.hour().minute()) }
    if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
      return date.formatted(style.weekday(.abbreviated))
    }
    if calendar.isDate(date, equalTo: now, toGranularity: .year) {
      return date.formatted(style.day().month(.abbreviated))
    }
    return date.formatted(style.day().month(.twoDigits).year(.twoDigits))
  }
}
