import Foundation

/// A person found in the homeserver's user directory.
public struct Person: Sendable, Equatable, Identifiable, Hashable {
  /// The Matrix user id.
  public let id: String
  public let displayName: String?

  public init(id: String, displayName: String?) {
    self.id = id
    self.displayName = displayName
  }

  public var name: String { displayName.flatMap { $0.isEmpty ? nil : $0 } ?? id }
}

public enum PeopleError: Error, Sendable, Equatable {
  case notSignedIn
  case requestFailed
}

/// Finds people and starts chats with them, as the Flutter new chat and new group pages do. Implemented in MatrixData;
/// no SDK type appears here (ADR 0006).
public protocol PeopleRepository: Sendable {
  /// People whose name or Matrix id matches the search text, from the homeserver's user directory.
  func search(_ text: String) async throws(PeopleError) -> [Person]

  /// The direct chat with `userId`: the existing one, or a new encrypted one inviting them. Returns the room id.
  func directChat(with userId: String) async throws(PeopleError) -> String

  /// A new private, encrypted group named `name` that invites `userIds`. Returns the room id.
  func createGroup(name: String, inviting userIds: [String]) async throws(PeopleError) -> String
}
