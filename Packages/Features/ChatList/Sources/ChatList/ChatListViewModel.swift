import Domain
import Foundation
import Observation

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
    case all, unread, favourites, people, groups
    public var id: Self { self }
    public var title: String {
      switch self {
      case .all: "All"
      case .unread: "Unread"
      case .favourites: "Favourites"
      case .people: "People"
      case .groups: "Groups"
      }
    }

    func includes(_ room: RoomSummary) -> Bool {
      switch self {
      case .all: true
      case .unread: room.unreadCount > 0 || room.mentionCount > 0
      case .favourites: room.isFavourite
      case .people: room.isDirect
      case .groups: !room.isDirect
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
    logOut: @escaping @MainActor () async -> Bool
  ) {
    self.spaces = spaces
    self.archive = archive
    self.publicRooms = publicRooms
    self.repository = repository
    self.media = media
    self.logOutAction = logOut
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
      onOpen: onOpen)
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

  /// The joined rooms that are not favourites.
  public var otherRooms: [RoomSummary] { joinedRooms.filter { !$0.isFavourite } }

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

  /// The row's preview: "sender: text", or the text alone when the sender is unknown; `nil` without a text message.
  public static func preview(of room: RoomSummary) -> String? {
    guard let text = room.lastMessageText else { return nil }
    guard let sender = room.lastMessageSender else { return text }
    return "\(sender): \(text)"
  }

  /// The time beside a room: the hour today, the weekday this week, the date before, as the Flutter chat list writes it.
  public static func timeText(_ date: Date, now: Date = .now, calendar: Calendar = .current)
    -> String
  {
    if calendar.isDate(date, inSameDayAs: now) { return date.formatted(.dateTime.hour().minute()) }
    if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
      return date.formatted(.dateTime.weekday(.abbreviated))
    }
    return date.formatted(.dateTime.day().month(.twoDigits).year(.twoDigits))
  }
}
