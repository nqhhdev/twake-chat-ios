import Foundation

/// A message an in-chat search found.
public struct RoomSearchResult: Sendable, Equatable, Identifiable {
  public let eventId: String
  public let senderId: String
  public let senderName: String
  public let date: Date
  public let text: String
  /// The room of the message, for a search across every room.
  public let roomId: String?

  public init(
    eventId: String, senderId: String, senderName: String, date: Date, text: String,
    roomId: String? = nil
  ) {
    self.roomId = roomId
    self.eventId = eventId
    self.senderId = senderId
    self.senderName = senderName
    self.date = date
    self.text = text
  }

  public var id: String { eventId }
}

/// One page of a server search.
public struct RoomSearchPage: Sendable, Equatable {
  /// Newest first.
  public let results: [RoomSearchResult]
  /// Where the next page starts; `nil` after the last one.
  public let nextBatch: String?

  public init(results: [RoomSearchResult], nextBatch: String?) {
    self.results = results
    self.nextBatch = nextBatch
  }
}

public enum RoomSearchError: Error, Sendable, Equatable {
  case notSignedIn
  case requestFailed
}

/// The homeserver's message search (Flutter `ServerSearchController`), which sees only messages that are not
/// encrypted; an encrypted chat is searched on the device. Implemented in MatrixData (ADR 0006).
public protocol RoomSearchRepository: Sendable {
  /// The messages of `roomId` that match `term`, newest first, from `nextBatch` (`nil` for the first page).
  func search(_ term: String, roomId: String, from nextBatch: String?) async throws(RoomSearchError)
    -> RoomSearchPage
  /// The messages of every room the user is in that match `term`, newest first.
  func searchEverywhere(_ term: String, from nextBatch: String?) async throws(RoomSearchError)
    -> RoomSearchPage

  func searchOnDevice(_ term: String, roomId: String) async -> [RoomSearchResult]
}

extension RoomSearchRepository {
  public func searchOnDevice(_ term: String, roomId: String) async -> [RoomSearchResult] { [] }

  public func searchEverywhere(_ term: String, from nextBatch: String?)
    async throws(RoomSearchError) -> RoomSearchPage
  {
    throw .requestFailed
  }
}
