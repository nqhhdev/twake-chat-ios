import Domain
import Foundation
import Observation

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

  public init(
    roomId: String, repository: any RoomDetailsRepository, onLeft: @escaping @MainActor () -> Void
  ) {
    self.roomId = roomId
    self.repository = repository
    self.onLeft = onLeft
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
