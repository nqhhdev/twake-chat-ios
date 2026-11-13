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
      return RoomDetails(
        id: info.id, name: info.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? info.id,
        topic: info.topic.flatMap { $0.isEmpty ? nil : $0 }, alias: info.canonicalAlias,
        isDirect: info.isDirect,
        isEncrypted: isEncrypted, isPublic: info.isPublic ?? false,
        joinedMemberCount: Int(clamping: info.joinedMembersCount))
    } catch {
      throw .requestFailed
    }
  }

  public func members(roomId: String) async throws(RoomDetailsError) -> [Domain.RoomMember] {
    let room = try await room(roomId)
    do {
      let iterator = try await room.members()
      var members: [Domain.RoomMember] = []
      while let chunk = iterator.nextChunk(chunkSize: Self.chunkSize) {
        for member in chunk {
          switch member.membership {
          case .join:
            members.append(
              .init(id: member.userId, displayName: member.displayName, membership: .joined))
          case .invite:
            members.append(
              .init(id: member.userId, displayName: member.displayName, membership: .invited))
          default: continue
          }
        }
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
    do {
      try await room.leave()
    } catch {
      throw .requestFailed
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

  private func room(_ roomId: String) async throws(RoomDetailsError) -> Room {
    guard let client = await clientProxy() else { throw .notSignedIn }
    guard let room = try? client.client.getRoom(roomId: roomId) else { throw .roomNotFound }
    return room
  }
}
