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

  private var _channel: ChannelSettings?
  private var _channelFails = false
  private var _channelChanges: [String] = []

  public var channel: ChannelSettings? {
    get { lock.withLock { _channel } }
    set { lock.withLock { _channel = newValue } }
  }
  public var channelFails: Bool {
    get { lock.withLock { _channelFails } }
    set { lock.withLock { _channelFails = newValue } }
  }
  public var channelChanges: [String] { lock.withLock { _channelChanges } }

  public func channelSettings(roomId: String) async -> ChannelSettings? { channel }

  public func setGifs(_ enabled: Bool, roomId: String) async throws(RoomDetailsError) {
    let fails = lock.withLock {
      _channelChanges.append("gifs \(enabled)")
      return _channelFails
    }
    if fails { throw .requestFailed }
    lock.withLock {
      if let current = _channel {
        _channel = ChannelSettings(isOwner: current.isOwner, gifsEnabled: enabled)
      }
    }
  }

  /// Fed by tests to report a room change, as the SDK does on a sync.
  public let roomChanges = AsyncStream<Void>.makeStream()

  public func changes(roomId: String) async -> AsyncStream<Void> { roomChanges.stream }

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

  private var _mode: (NotificationMode, Bool) = (.allMessages, true)
  private var _setModeResult: Result<Void, RoomDetailsError> = .success(())

  public var setModeResult: Result<Void, RoomDetailsError> {
    get { lock.withLock { _setModeResult } }
    set { lock.withLock { _setModeResult = newValue } }
  }

  public var mode: (NotificationMode, Bool) { lock.withLock { _mode } }

  public func notificationMode(roomId: String) async throws(RoomDetailsError)
    -> (mode: NotificationMode, isDefault: Bool)
  {
    let current = mode
    return (current.0, current.1)
  }

  public func setNotificationMode(_ mode: NotificationMode?, roomId: String)
    async throws(RoomDetailsError)
  {
    try setModeResult.get()
    lock.withLock { _mode = mode.map { ($0, false) } ?? (.allMessages, true) }
  }

  public func leave(roomId: String) async throws(RoomDetailsError) {
    lock.withLock { _leftRooms.append(roomId) }
    try leaveResult.get()
  }

  private var _changes: [String] = []
  private var _changeResult: Result<Void, RoomDetailsError> = .success(())

  /// "name …", "topic …" and "invite …" in order.
  public var changes: [String] { lock.withLock { _changes } }

  /// What rename, setTopic and invite throw, if anything.
  public var changeResult: Result<Void, RoomDetailsError> {
    get { lock.withLock { _changeResult } }
    set { lock.withLock { _changeResult = newValue } }
  }

  public func rename(_ name: String, roomId: String) async throws(RoomDetailsError) {
    try changeResult.get()
    lock.withLock { _changes.append("name \(name)") }
  }

  public func setTopic(_ topic: String, roomId: String) async throws(RoomDetailsError) {
    try changeResult.get()
    lock.withLock { _changes.append("topic \(topic)") }
  }

  @discardableResult
  public func invite(userIds: [String], roomId: String) async throws(RoomDetailsError) -> [String] {
    try changeResult.get()
    lock.withLock { _changes.append("invite \(userIds.joined(separator: ","))") }
    return []
  }

  public func setAvatar(_ picture: PictureUpload, roomId: String) async throws(RoomDetailsError) {
    try changeResult.get()
    lock.withLock { _changes.append("avatar \(picture.width)x\(picture.height)") }
  }

  public func removeAvatar(roomId: String) async throws(RoomDetailsError) {
    try changeResult.get()
    lock.withLock { _changes.append("remove avatar") }
  }

  public func remove(userId: String, roomId: String) async throws(RoomDetailsError) {
    try changeResult.get()
    lock.withLock {
      _changes.append("remove \(userId)")
      _members.removeAll { $0.id == userId }
    }
  }

  private var _banned: [RoomMember] = []

  /// The people banned; banning moves a member here, unbanning drops them.
  public var bannedMembers: [RoomMember] {
    get { lock.withLock { _banned } }
    set { lock.withLock { _banned = newValue } }
  }

  public func ban(userId: String, roomId: String) async throws(RoomDetailsError) {
    try changeResult.get()
    lock.withLock {
      _changes.append("ban \(userId)")
      if let member = _members.first(where: { $0.id == userId }) {
        _banned.append(
          RoomMember(id: member.id, displayName: member.displayName, membership: .banned))
      }
      _members.removeAll { $0.id == userId }
    }
  }

  public func banned(roomId: String) async throws(RoomDetailsError) -> [RoomMember] {
    bannedMembers
  }

  public func unban(userId: String, roomId: String) async throws(RoomDetailsError) {
    try changeResult.get()
    lock.withLock {
      _changes.append("unban \(userId)")
      _banned.removeAll { $0.id == userId }
    }
  }

  public func setRole(_ role: RoomMember.Role, userId: String, roomId: String)
    async throws(RoomDetailsError)
  {
    try changeResult.get()
    lock.withLock { _changes.append("role \(userId) \(role)") }
  }

  public func setJoinRule(_ rule: RoomDetails.JoinRule, roomId: String)
    async throws(RoomDetailsError)
  {
    try changeResult.get()
    lock.withLock { _changes.append("join rule \(rule)") }
  }

  public func enableEncryption(roomId: String) async throws(RoomDetailsError) {
    try changeResult.get()
    lock.withLock { _changes.append("encryption") }
  }

  private var _presence: Presence?
  private var _presenceCalls: [String] = []

  /// What `presence(of:)` answers.
  public var presence: Presence? {
    get { lock.withLock { _presence } }
    set { lock.withLock { _presence = newValue } }
  }

  /// User ids `presence(of:)` was called with, in order.
  public var presenceCalls: [String] { lock.withLock { _presenceCalls } }

  public func presence(of userId: String) async -> Presence? {
    lock.withLock { _presenceCalls.append(userId) }
    return presence
  }
}
