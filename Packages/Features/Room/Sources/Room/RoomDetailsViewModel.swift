import DesignSystem
import Domain
import Foundation
import Observation
import SwiftUI

/// The chat details, as the Flutter app's `chat_details` page: the room's avatar, name, description and address,
/// whether it is encrypted, its members, and Leave. Leaving asks first, as the Flutter app does, then closes the chat.
@MainActor @Observable
public final class RoomDetailsViewModel {
  public enum State: Equatable {
    case loading
    case loaded(RoomDetails)
    case failed(String)
  }

  public let roomId: String
  public private(set) var state: State = .loading
  public private(set) var members: [RoomMember] = []
  public private(set) var isLeaving = false
  public private(set) var errorMessage: String?
  public var memberQuery = ""
  /// The room's notification mode, and whether it follows the account's default.
  public private(set) var notificationMode: NotificationMode?
  public private(set) var followsDefault = true

  @ObservationIgnored private let repository: any RoomDetailsRepository
  @ObservationIgnored private let onLeft: @MainActor () -> Void
  /// The app's people picker for inviting into this room (ADR 0005: the Room feature does not know People); `nil` hides
  /// "Add people". The closure it is given runs once people were invited.
  @ObservationIgnored public let invitePeople: InvitePeople?
  /// Loads the room's and members' pictures; `nil` shows initials.
  @ObservationIgnored let media: (any MediaRepository)?
  /// Makes a timeline of one kind of message of this room, for the Media, Files and Links tabs; `nil` hides them.
  @ObservationIgnored private let contentTimeline: ContentTimeline?
  /// Opens the direct chat with a user, found or created by the app (ADR 0005); returns whether it worked. `nil`
  /// hides Message on a member's profile.
  @ObservationIgnored let openDirectChat: (@MainActor (String) async -> Bool)?
  /// Blocks a user everywhere (Matrix ignore); `nil` hides Block on a member's profile.
  @ObservationIgnored private let blockUser: (@MainActor (String) async -> Bool)?
  public private(set) var isSaving = false

  public init(
    roomId: String, repository: any RoomDetailsRepository, onLeft: @escaping @MainActor () -> Void,
    invitePeople: InvitePeople? = nil, media: (any MediaRepository)? = nil,
    contentTimeline: ContentTimeline? = nil,
    openDirectChat: (@MainActor (String) async -> Bool)? = nil,
    block: (@MainActor (String) async -> Bool)? = nil
  ) {
    self.openDirectChat = openDirectChat
    self.blockUser = block
    self.roomId = roomId
    self.repository = repository
    self.onLeft = onLeft
    self.invitePeople = invitePeople
    self.media = media
    self.contentTimeline = contentTimeline
  }

  /// Whether the Media, Files and Links tabs show.
  public var hasContentTabs: Bool { contentTimeline != nil && media != nil }

  /// The tab listing one kind of message of this room.
  public func content(_ kind: RoomContentKind) -> RoomContentViewModel? {
    guard let contentTimeline, let media else { return nil }
    return RoomContentViewModel(kind: kind, repository: contentTimeline(kind), media: media)
  }

  /// Loads a picture as data, for an avatar.
  func picture(_ reference: MediaReference) async -> Data? {
    try? await media?.thumbnail(reference, width: 192, height: 192)
  }

  /// The room's picture as last loaded, or `nil`.
  var loadedAvatar: MediaReference? {
    if case .loaded(let details) = state { details.avatar } else { nil }
  }

  /// A new room picture is uploading.
  public private(set) var isUpdatingPicture = false

  /// Makes a prepared picture the room's avatar (Flutter `chat_details_edit`), then shows the room as it is now.
  public func setPicture(_ picture: PreparedPicture) async {
    await changePicture(failure: "Could not change the chat picture. Please try again.") {
      [repository, roomId] in
      try await repository.setAvatar(
        PictureUpload(
          data: picture.jpeg, mimeType: "image/jpeg", width: picture.side, height: picture.side),
        roomId: roomId)
    }
  }

  /// Removes the room's avatar; the chat shows its initial.
  public func removePicture() async {
    await changePicture(failure: "Could not remove the chat picture. Please try again.") {
      [repository, roomId] in try await repository.removeAvatar(roomId: roomId)
    }
  }

  private func changePicture(
    failure: String, _ change: @escaping () async throws -> Void
  ) async {
    guard !isUpdatingPicture else { return }
    isUpdatingPicture = true
    defer { isUpdatingPicture = false }
    errorMessage = nil
    do {
      try await change()
      if let details = try? await repository.details(roomId: roomId) { state = .loaded(details) }
    } catch {
      errorMessage = failure
    }
  }

  /// Saves a new name and topic, only what changed, then shows the room as it is now. Returns whether it worked.
  @discardableResult
  public func save(name: String, topic: String) async -> Bool {
    guard case .loaded(let details) = state, !isSaving else { return false }
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let topic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      errorMessage = "The name cannot be empty."
      return false
    }
    isSaving = true
    defer { isSaving = false }
    errorMessage = nil
    do {
      if name != details.name { try await repository.rename(name, roomId: roomId) }
      if topic != (details.topic ?? "") { try await repository.setTopic(topic, roomId: roomId) }
    } catch {
      errorMessage = "Could not save the changes. Please try again."
      return false
    }
    await load()
    return true
  }

  public func load() async {
    do {
      state = .loaded(try await repository.details(roomId: roomId))
    } catch {
      state = .failed("Could not load the chat details.")
      return
    }
    members = (try? await repository.members(roomId: roomId)) ?? []
    if let current = try? await repository.notificationMode(roomId: roomId) {
      notificationMode = current.mode
      followsDefault = current.isDefault
    }
  }

  /// Sets the room's own mode, or the account default with `nil`; goes back on failure.
  public func setNotificationMode(_ mode: NotificationMode?) async {
    let previous = (notificationMode, followsDefault)
    if let mode {
      notificationMode = mode
      followsDefault = false
    } else {
      followsDefault = true
    }
    do {
      try await repository.setNotificationMode(mode, roomId: roomId)
      if mode == nil, let current = try? await repository.notificationMode(roomId: roomId) {
        notificationMode = current.mode
      }
    } catch {
      (notificationMode, followsDefault) = previous
      errorMessage = "Could not change the notifications. Please try again."
    }
  }

  /// The members whose name or Matrix id contains the search text.
  public var filteredMembers: [RoomMember] {
    let query = memberQuery.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else { return members }
    return members.filter {
      $0.name.localizedCaseInsensitiveContains(query)
        || $0.id.localizedCaseInsensitiveContains(query)
    }
  }

  /// The people banned from the room; `nil` until loaded.
  public private(set) var banned: [RoomMember]?

  public func loadBanned() async {
    banned = (try? await repository.banned(roomId: roomId)) ?? []
  }

  /// Bans a member (Flutter `removed`): they are removed and kept out. Returns whether it worked.
  @discardableResult
  public func ban(_ member: RoomMember) async -> Bool {
    guard member.canBeBanned else { return false }
    return await change("Could not ban \(member.name). Please try again.") {
      [repository, roomId] in try await repository.ban(userId: member.id, roomId: roomId)
    }
  }

  /// Lets a banned person back.
  @discardableResult
  public func unban(_ member: RoomMember) async -> Bool {
    let done = await change("Could not unban \(member.name). Please try again.") {
      [repository, roomId] in try await repository.unban(userId: member.id, roomId: roomId)
    }
    if done { withAnimation { banned?.removeAll { $0.id == member.id } } }
    return done
  }

  /// Gives a member a role among those the user may give (Flutter `assign_roles`).
  @discardableResult
  public func setRole(_ role: RoomMember.Role, for member: RoomMember) async -> Bool {
    guard member.assignableRoles.contains(role), role != member.role else { return false }
    return await change("Could not change the role of \(member.name). Please try again.") {
      [repository, roomId] in
      try await repository.setRole(role, userId: member.id, roomId: roomId)
    }
  }

  /// Changes who can join (Flutter `room_access`). Public is refused for an encrypted room that is not public
  /// already, as the Flutter app does.
  public func setJoinRule(_ rule: RoomDetails.JoinRule) async {
    guard case .loaded(let details) = state, details.canChangeAccess, rule != details.joinRule
    else { return }
    if rule == .public, details.isEncrypted { return }
    await change("Could not change who can join. Please try again.") { [repository, roomId] in
      try await repository.setJoinRule(rule, roomId: roomId)
    }
  }

  /// Turns encryption on for good.
  public func enableEncryption() async {
    guard case .loaded(let details) = state, details.canEnableEncryption else { return }
    await change("Could not turn on encryption. Please try again.") { [repository, roomId] in
      try await repository.enableEncryption(roomId: roomId)
    }
  }

  /// Runs a change, then shows the room and its members as they are now.
  @discardableResult
  private func change(
    _ failure: String, _ action: @escaping () async throws -> Void
  ) async -> Bool {
    errorMessage = nil
    do {
      try await action()
    } catch {
      errorMessage = failure
      return false
    }
    if let details = try? await repository.details(roomId: roomId) { state = .loaded(details) }
    members = (try? await repository.members(roomId: roomId)) ?? members
    return true
  }

  /// Removes a member from the room (Flutter `removeFromGroupChat`), then shows the members as they are now. Returns
  /// whether it worked.
  @discardableResult
  public func remove(_ member: RoomMember) async -> Bool {
    guard member.canBeRemoved else { return false }
    errorMessage = nil
    do {
      try await repository.remove(userId: member.id, roomId: roomId)
      members = (try? await repository.members(roomId: roomId)) ?? members
      return true
    } catch {
      errorMessage = "Could not remove \(member.name). Please try again."
      return false
    }
  }

  /// Opens the direct chat with a member (Flutter `openNewChat`); the app closes this room to show it.
  public func message(_ member: RoomMember) async {
    guard let openDirectChat, !member.isOwn else { return }
    errorMessage = nil
    if await !openDirectChat(member.id) {
      errorMessage = "Could not open the chat with \(member.name). Please try again."
    }
  }

  /// Whether a member's profile offers Block.
  func canBlock(_ member: RoomMember) -> Bool { blockUser != nil && !member.isOwn }

  /// Blocks a member: nothing from them shows any more, in any room. Returns whether it worked.
  @discardableResult
  public func block(_ member: RoomMember) async -> Bool {
    guard let blockUser, !member.isOwn else { return false }
    errorMessage = nil
    guard await blockUser(member.id) else {
      errorMessage = "Could not block \(member.name). Please try again."
      return false
    }
    return true
  }

  public func leave() async {
    guard !isLeaving else { return }
    isLeaving = true
    defer { isLeaving = false }
    errorMessage = nil
    do {
      try await repository.leave(roomId: roomId)
      onLeft()
    } catch {
      errorMessage = "Could not leave the chat. Please try again."
    }
  }
}

/// One details page is one value: the room screen pushes it with `navigationDestination(item:)`.
extension RoomDetailsViewModel: Hashable {
  nonisolated public static func == (lhs: RoomDetailsViewModel, rhs: RoomDetailsViewModel) -> Bool {
    lhs === rhs
  }
  nonisolated public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// Shows the app's people picker for one room; the closure runs once people were invited.
public struct InvitePeople {
  public let view:
    @MainActor (_ roomId: String, _ onInvited: @escaping @MainActor () -> Void) -> AnyView

  public init(
    _ view:
      @escaping @MainActor (_ roomId: String, _ onInvited: @escaping @MainActor () -> Void) ->
      AnyView
  ) {
    self.view = view
  }
}
