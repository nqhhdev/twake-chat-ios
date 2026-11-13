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
