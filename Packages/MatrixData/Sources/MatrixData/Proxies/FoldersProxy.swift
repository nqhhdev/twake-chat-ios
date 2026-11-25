import Domain
import Foundation
import MatrixRustSDK

public actor FoldersProxy: FoldersRepository {
  private let clientProxy: @Sendable () async -> ClientProxy?

  public init(authentication: MatrixAuthenticationRepository) {
    clientProxy = { await authentication.clientProxy }
  }

  static func syncFilter() -> [String: Any] {
    [
      "presence": ["types": [String]()],
      "account_data": ["types": [FolderContent.accountDataType]],
      "room": [
        "timeline": ["limit": 0],
        "state": ["types": [String]()],
        "ephemeral": ["types": [String]()],
        "account_data": ["types": [FolderContent.tagEventType]],
        "include_leave": false,
      ],
    ]
  }

  static func syncPath() -> String? {
    guard
      let data = try? JSONSerialization.data(withJSONObject: syncFilter(), options: .sortedKeys),
      let filter = String(data: data, encoding: .utf8),
      let encoded = filter.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
    else { return nil }
    return "sync?timeout=0&filter=\(encoded)"
  }

  static func tagPath(userId: String, roomId: String, tag: String) -> String {
    "user/\(ClientServerRequest.encode(userId))/rooms/\(ClientServerRequest.encode(roomId))/tags/"
      + ClientServerRequest.encode(tag)
  }

  public func load() async throws(FoldersError) -> FolderState {
    guard let client = await clientProxy()?.client else { throw .notSignedIn }
    guard let path = Self.syncPath(),
      let request = ClientServerRequest.make(client: client, path: path),
      let response = await ClientServerRequest.object(request)
    else { throw .requestFailed }
    return FolderContent.state(fromSync: response)
  }

  public func save(_ shown: [Folder]) async throws(FoldersError) {
    guard let client = await clientProxy()?.client else { throw .notSignedIn }
    let stored = try? await client.accountData(eventType: FolderContent.accountDataType)
    let current =
      stored.flatMap { $0 }.flatMap { $0.data(using: .utf8) }
      .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    let content = FolderContent.write(Folder.withHiddenBuiltins(shown), current: current)
    guard let data = try? JSONSerialization.data(withJSONObject: content),
      let json = String(data: data, encoding: .utf8)
    else { throw .requestFailed }
    do {
      try await client.setAccountData(eventType: FolderContent.accountDataType, content: json)
    } catch {
      DebugLog.failure("saveFolders", error)
      throw .requestFailed
    }
  }

  public func apply(_ changes: [FolderTagChange]) async throws(FoldersError) {
    guard let client = await clientProxy()?.client else { throw .notSignedIn }
    guard let userId = try? client.userId() else { throw .requestFailed }
    var failed = false
    for change in changes {
      guard
        let request = ClientServerRequest.make(
          client: client,
          path: Self.tagPath(userId: userId, roomId: change.roomId, tag: change.tag),
          method: change.isIn ? "PUT" : "DELETE", json: change.isIn ? [:] : nil)
      else {
        failed = true
        continue
      }
      if await !ClientServerRequest.succeeds(request) { failed = true }
    }
    if failed { throw .requestFailed }
  }
}
