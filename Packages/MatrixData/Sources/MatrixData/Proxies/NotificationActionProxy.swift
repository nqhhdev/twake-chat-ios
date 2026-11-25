import Domain
import Foundation
import MatrixRustSDK

public actor NotificationActionProxy: NotificationActionRepository {
  private let clientProxy: @Sendable () async -> ClientProxy?
  private let readiness: Duration

  public init(authentication: MatrixAuthenticationRepository, readiness: Duration = .seconds(15)) {
    clientProxy = { await authentication.clientProxy }
    self.readiness = readiness
  }

  public func reply(text: String, roomId: String, threadId: String?, eventId: String)
    async throws(NotificationActionError)
  {
    guard let content = Self.replyContent(text: text, threadId: threadId, eventId: eventId) else {
      return
    }
    let room = try await room(roomId)
    do {
      try await room.sendRaw(eventType: "m.room.message", content: content)
    } catch {
      throw .requestFailed
    }
    try? await room.markAsRead(receiptType: .read)
    try? await room.setUnreadFlag(newValue: false)
  }

  public func markAsRead(roomId: String) async throws(NotificationActionError) {
    let room = try await room(roomId)
    do {
      try await room.markAsRead(receiptType: .read)
      try await room.setUnreadFlag(newValue: false)
    } catch {
      throw .requestFailed
    }
  }

  static func replyContent(text: String, threadId: String?, eventId: String) -> String? {
    let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty else { return nil }
    var content: [String: Any] = ["msgtype": "m.text", "body": body]
    if let threadId, !threadId.isEmpty {
      content["m.relates_to"] = [
        "rel_type": "m.thread", "event_id": threadId, "is_falling_back": true,
        "m.in_reply_to": ["event_id": eventId],
      ]
    }
    guard let data = try? JSONSerialization.data(withJSONObject: content, options: [.sortedKeys])
    else { return nil }
    return String(decoding: data, as: UTF8.self)
  }

  private func room(_ roomId: String) async throws(NotificationActionError) -> Room {
    let client = try await readyClient()
    guard let room = try? await client.room(id: roomId) else { throw .roomNotFound }
    return room
  }

  private func readyClient() async throws(NotificationActionError) -> ClientProxy {
    let deadline = ContinuousClock.now + readiness
    while true {
      if let client = await clientProxy() { return client }
      guard ContinuousClock.now < deadline, !Task.isCancelled else { throw .notSignedIn }
      try? await Task.sleep(for: .milliseconds(250))
    }
  }
}
