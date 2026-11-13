import Domain
import Foundation

/// A hand-written `RoomDetailsRepository` for tests (ADR 0010).
public final class FakeRoomDetailsRepository: RoomDetailsRepository, @unchecked Sendable {
  private let lock = NSLock()
  private var _details: Result<RoomDetails, RoomDetailsError> = .failure(.roomNotFound)
  private var _members: [RoomMember] = []
  private var _leaveResult: Result<Void, RoomDetailsError> = .success(())
  private var _leftRooms: [String] = []

  public init() {}

  public var detailsResult: Result<RoomDetails, RoomDetailsError> {
    get { lock.withLock { _details } }
    set { lock.withLock { _details = newValue } }
  }

  public var members: [RoomMember] {
    get { lock.withLock { _members } }
    set { lock.withLock { _members = newValue } }
  }

  public var leaveResult: Result<Void, RoomDetailsError> {
    get { lock.withLock { _leaveResult } }
    set { lock.withLock { _leaveResult = newValue } }
  }

  public var leftRooms: [String] { lock.withLock { _leftRooms } }

  public func details(roomId: String) async throws(RoomDetailsError) -> RoomDetails {
    try detailsResult.get()
  }

  public func members(roomId: String) async throws(RoomDetailsError) -> [RoomMember] {
    members
  }

  public func leave(roomId: String) async throws(RoomDetailsError) {
    lock.withLock { _leftRooms.append(roomId) }
    try leaveResult.get()
  }
}
