import Domain
import Foundation
import MatrixRustSDK

/// `RoomDetailsRepository` on the SDK room (ADR 0006): room info, members and leaving. Nothing here logs.
public actor RoomDetailsProxy: RoomDetailsRepository {
  /// How many members one read takes from the SDK's member iterator.
  static let chunkSize: UInt32 = 500

  private let clientProxy: @Sendable () async -> ClientProxy?

  public init(authentication: MatrixAuthenticationRepository) {
    clientProxy = { await authentication.clientProxy }
  }

  public func details(roomId: String) async throws(RoomDetailsError) -> RoomDetails {
    let room = try await room(roomId)
    do {
      let info = try await room.roomInfo()
      let isEncrypted = await room.isEncrypted()
      let ownUserId = room.ownUserId()
      let powerLevels = try? await room.getPowerLevels()
      let canEdit =
        (try? powerLevels?.canUserSendState(userId: ownUserId, stateEvent: .roomName)) ?? false
      let canInvite = (try? powerLevels?.canUserInvite(userId: ownUserId)) ?? false
      let canChangeAccess = powerLevels?.canOwnUserSendState(stateEvent: .roomJoinRules) ?? false
      let canEncrypt = powerLevels?.canOwnUserSendState(stateEvent: .roomEncryption) ?? false
      return RoomDetails(
        id: info.id, name: info.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? info.id,
        topic: info.topic.flatMap { $0.isEmpty ? nil : $0 }, alias: info.canonicalAlias,
        isDirect: info.isDirect,
        isEncrypted: isEncrypted, isPublic: info.isPublic ?? false,
        joinedMemberCount: Int(clamping: info.joinedMembersCount), canEdit: canEdit,
        canInvite: canInvite, avatar: RoomSummaryMapper.avatar(of: info),
        joinRule: Self.joinRule(info.joinRule), canChangeAccess: canChangeAccess && !info.isDirect,
        canEnableEncryption: canEncrypt && !isEncrypted,
        canBan: powerLevels?.canOwnUserBan() ?? false,
        canRedactOthers: powerLevels?.canOwnUserRedactOther() ?? false,
        successorRoomId: info.successorRoom?.roomId,
        directUserId: info.isDirect && info.heroes.count == 1 ? info.heroes.first?.userId : nil,
        canSendMessages: powerLevels?.canOwnUserSendMessage(message: .roomMessage) ?? true,
        canNotifyRoom: !info.isDirect
          && (powerLevels?.canOwnUserTriggerRoomNotification() ?? false),
        isBroadcast: !info.isDirect && !info.isSpace
          && (powerLevels?.values().eventsDefault ?? 0) >= 50
      )
    } catch {
      throw .requestFailed
    }
  }

  public func members(roomId: String) async throws(RoomDetailsError) -> [Domain.RoomMember] {
    let room = try await room(roomId)
    do {
      let iterator = try await room.members()
      var all: [MatrixRustSDK.RoomMember] = []
      while let chunk = iterator.nextChunk(chunkSize: Self.chunkSize) { all += chunk }
      let ownUserId = room.ownUserId()
      let powerLevels = try? await room.getPowerLevels()
      let canKick = powerLevels?.canOwnUserKick() ?? false
      let canBan = powerLevels?.canOwnUserBan() ?? false
      let canChangeRoles = powerLevels?.canOwnUserSendState(stateEvent: .roomPowerLevels) ?? false
      let ownLevel = all.first { $0.userId == ownUserId }.map { Self.level($0.powerLevel) } ?? 0
      var members: [Domain.RoomMember] = []
      for member in all {
        let membership: Domain.RoomMember.Membership
        switch member.membership {
        case .join: membership = .joined
        case .invite: membership = .invited
        default: continue
        }
        let isOwn = member.userId == ownUserId
        let outranked = !isOwn && Self.level(member.powerLevel) < ownLevel
        members.append(
          .init(
            id: member.userId, displayName: member.displayName, membership: membership,
            avatar: RoomSummaryMapper.avatar(member.avatarUrl),
            role: Self.role(member.suggestedRoleForPowerLevel), isOwn: isOwn,
            canBeRemoved: canKick && outranked, canBeBanned: canBan && outranked,
            assignableRoles: canChangeRoles && outranked
              ? Self.assignableRoles(ownLevel: ownLevel) : []))
      }
      return members.sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
    } catch {
      throw .requestFailed
    }
  }

  public func leave(roomId: String) async throws(RoomDetailsError) {
    let room = try await room(roomId)
    let info = try? await room.roomInfo()
    do {
      try await room.leave()
    } catch {
      throw .requestFailed
    }
    if let client = await clientProxy()?.client {
      await ArchiveAccountData.archive(room, info: info, client: client)
    }
  }

  public func notificationMode(roomId: String) async throws(RoomDetailsError)
    -> (mode: NotificationMode, isDefault: Bool)
  {
    let room = try await room(roomId)
    guard let client = await clientProxy() else { throw .notSignedIn }
    do {
      let isEncrypted = await room.isEncrypted()
      let isDirect = await room.isDirect()
      let settings = try await client.client.getNotificationSettings().getRoomNotificationSettings(
        roomId: roomId, isEncrypted: isEncrypted, isOneToOne: isDirect)
      return (NotificationModeMapper.domain(settings.mode), settings.isDefault)
    } catch {
      throw .requestFailed
    }
  }

  public func setNotificationMode(_ mode: NotificationMode?, roomId: String)
    async throws(RoomDetailsError)
  {
    guard let client = await clientProxy() else { throw .notSignedIn }
    let settings = await client.client.getNotificationSettings()
    do {
      if let mode {
        try await settings.setRoomNotificationMode(
          roomId: roomId, mode: NotificationModeMapper.sdk(mode))
      } else {
        try await settings.restoreDefaultRoomNotificationMode(roomId: roomId)
      }
    } catch {
      throw .requestFailed
    }
  }

  public func rename(_ name: String, roomId: String) async throws(RoomDetailsError) {
    let room = try await room(roomId)
    do { try await room.setName(name: name) } catch { throw .requestFailed }
  }

  public func setTopic(_ topic: String, roomId: String) async throws(RoomDetailsError) {
    let room = try await room(roomId)
    do { try await room.setTopic(topic: topic) } catch { throw .requestFailed }
  }

  public func setAvatar(_ picture: PictureUpload, roomId: String) async throws(RoomDetailsError) {
    let room = try await room(roomId)
    let info = ImageInfo(
      height: UInt64(max(0, picture.height)), width: UInt64(max(0, picture.width)),
      mimetype: picture.mimeType, size: UInt64(picture.data.count), thumbnailInfo: nil,
      thumbnailSource: nil, blurhash: nil, isAnimated: nil)
    do {
      try await room.uploadAvatar(mimeType: picture.mimeType, data: picture.data, mediaInfo: info)
    } catch {
      throw .requestFailed
    }
  }

  public func removeAvatar(roomId: String) async throws(RoomDetailsError) {
    let room = try await room(roomId)
    do { try await room.removeAvatar() } catch { throw .requestFailed }
  }

  public func remove(userId: String, roomId: String) async throws(RoomDetailsError) {
    let room = try await room(roomId)
    do {
      try await room.kickUser(userId: userId, reason: nil)
    } catch {
      throw .requestFailed
    }
  }

  public func ban(userId: String, roomId: String) async throws(RoomDetailsError) {
    let room = try await room(roomId)
    do { try await room.banUser(userId: userId, reason: nil) } catch { throw .requestFailed }
  }

  public func banned(roomId: String) async throws(RoomDetailsError) -> [Domain.RoomMember] {
    let room = try await room(roomId)
    do {
      let iterator = try await room.members()
      var banned: [Domain.RoomMember] = []
      while let chunk = iterator.nextChunk(chunkSize: Self.chunkSize) {
        for member in chunk where member.membership == .ban {
          banned.append(
            .init(
              id: member.userId, displayName: member.displayName, membership: .banned,
              avatar: RoomSummaryMapper.avatar(member.avatarUrl)))
        }
      }
      return banned.sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
    } catch {
      throw .requestFailed
    }
  }

  public func unban(userId: String, roomId: String) async throws(RoomDetailsError) {
    let room = try await room(roomId)
    do { try await room.unbanUser(userId: userId, reason: nil) } catch { throw .requestFailed }
  }

  public func setRole(_ role: Domain.RoomMember.Role, userId: String, roomId: String)
    async throws(RoomDetailsError)
  {
    let room = try await room(roomId)
    do {
      try await room.updatePowerLevelsForUsers(
        updates: [UserPowerLevelUpdate(userId: userId, powerLevel: Self.powerLevel(of: role))])
    } catch {
      throw .requestFailed
    }
  }

  public func setJoinRule(_ rule: RoomDetails.JoinRule, roomId: String)
    async throws(RoomDetailsError)
  {
    let room = try await room(roomId)
    let sdkRule: JoinRule =
      switch rule {
      case .invite: .invite
      case .knock: .knock
      case .public: .public
      }
    do { try await room.updateJoinRules(newRule: sdkRule) } catch { throw .requestFailed }
  }

  public func enableEncryption(roomId: String) async throws(RoomDetailsError) {
    let room = try await room(roomId)
    do { try await room.enableEncryption() } catch { throw .requestFailed }
  }

  /// The power level of a role, as Matrix clients use them: 100 admin, 50 moderator, 0 member.
  static func powerLevel(of role: Domain.RoomMember.Role) -> Int64 {
    switch role {
    case .creator, .administrator: 100
    case .moderator: 50
    case .user: 0
    }
  }

  /// The roles a user of `ownLevel` may give: never above their own.
  static func assignableRoles(ownLevel: Int64) -> [Domain.RoomMember.Role] {
    [.user, .moderator, .administrator].filter { powerLevel(of: $0) <= ownLevel }
  }

  static func joinRule(_ rule: JoinRule?) -> RoomDetails.JoinRule? {
    switch rule {
    case .invite: .invite
    case .knock: .knock
    case .public: .public
    default: nil
    }
  }

  /// A power level as a number; a room creator's (room version 12) is above every other.
  static func level(_ powerLevel: PowerLevel) -> Int64 {
    switch powerLevel {
    case .infinite: .max
    case .value(let value): value
    }
  }

  static func role(_ role: RoomMemberRole) -> Domain.RoomMember.Role {
    switch role {
    case .creator: .creator
    case .administrator: .administrator
    case .moderator: .moderator
    case .user: .user
    }
  }

  public func invite(userIds: [String], roomId: String) async throws(RoomDetailsError) {
    let room = try await room(roomId)
    do {
      for userId in userIds { try await room.inviteUserById(userId: userId) }
    } catch {
      throw .requestFailed
    }
  }

  public func statusMessage(of userId: String) async -> String? {
    guard let client = await clientProxy(),
      let request = ClientServerRequest.make(
        client: client.client, path: "presence/\(ClientServerRequest.encode(userId))/status"),
      let object = await ClientServerRequest.object(request)
    else { return nil }
    return (object["status_msg"] as? String).flatMap { $0.isEmpty ? nil : $0 }
  }

  public func presence(of userId: String) async -> Presence? {
    guard let client = await clientProxy(),
      let request = ClientServerRequest.make(
        client: client.client, path: "presence/\(ClientServerRequest.encode(userId))/status"),
      let object = await ClientServerRequest.object(request)
    else { return nil }
    return Presence.from(object)
  }

  /// Reads each joined group's member from the local store; at most `limit` rooms, so a huge account stays quick.
  public func roomsInCommon(with userId: String) async -> [RoomInCommon] {
    guard let client = await clientProxy() else { return [] }
    var found: [RoomInCommon] = []
    for room in client.client.rooms().prefix(300) where room.membership() == .joined {
      guard !(await room.isDirect()), !room.isSpace(),
        let member = try? await room.member(userId: userId), member.membership == .join
      else { continue }
      let info = try? await room.roomInfo()
      found.append(
        RoomInCommon(
          id: room.id(), name: room.displayName() ?? room.id(),
          avatar: info.flatMap(RoomSummaryMapper.avatar(of:))))
    }
    return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  /// The SDK reports a new room info for each change of the room's state, members included (twake-on-matrix #2233,
  /// #1154: the member list stayed stale until the screen was reopened).
  public func changes(roomId: String) async -> AsyncStream<Void> {
    guard let room = try? await room(roomId) else { return AsyncStream { $0.finish() } }
    let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let handle = room.subscribeToRoomInfoUpdates(listener: RoomInfoChanges { continuation.yield() })
    continuation.onTermination = { _ in handle.cancel() }
    return stream
  }

  private func room(_ roomId: String) async throws(RoomDetailsError) -> Room {
    guard let client = await clientProxy() else { throw .notSignedIn }
    guard let room = try? client.client.getRoom(roomId: roomId) else { throw .roomNotFound }
    return room
  }
}

/// Passes each room info the SDK reports on as a bare change.
private final class RoomInfoChanges: RoomInfoListener {
  private let onChange: @Sendable () -> Void

  init(onChange: @escaping @Sendable () -> Void) {
    self.onChange = onChange
  }

  func call(roomInfo: RoomInfo) { onChange() }
}
