import Domain
import Foundation
import MatrixRustSDK

public actor NotificationContentProxy: NotificationContentRepository {
  private let authentication: MatrixAuthenticationRepository

  public init(authentication: MatrixAuthenticationRepository) {
    self.authentication = authentication
  }

  static let retryPauses: [Duration] = [.seconds(1), .seconds(2)]

  public func content(roomId: String, eventId: String) async -> NotificationOutcome {
    guard (try? await authentication.restoreSession()) != nil,
      let client = await authentication.clientProxy?.client,
      let notifications = try? await client.notificationClient(processSetup: .multipleProcesses)
    else { return .generic }
    let ownUserId = try? client.userId()
    var pauses = Self.retryPauses[...]
    while true {
      let status = try? await notifications.getNotification(roomId: roomId, eventId: eventId)
      guard Self.isWorthRetrying(status), let pause = pauses.popFirst(), !Task.isCancelled else {
        let outcome = Self.outcome(of: status, ownUserId: ownUserId)
        return await Self.withAvatars(outcome, of: status, client: client)
      }
      try? await Task.sleep(for: pause)
    }
  }

  static let avatarSize: UInt64 = 96
  static let avatarTimeout: Duration = .seconds(3)

  private static func withAvatars(
    _ outcome: NotificationOutcome, of status: NotificationStatus?, client: Client
  ) async -> NotificationOutcome {
    guard case .show(var content) = outcome, case .event(let item)? = status else {
      return outcome
    }
    let roomURL = content.isDirect ? nil : item.roomInfo.avatarUrl
    async let sender = avatar(item.senderInfo.avatarUrl, client: client)
    async let room = avatar(roomURL, client: client)
    content.senderAvatar = await sender
    content.roomAvatar = await room
    return .show(content)
  }

  private static func avatar(_ url: String?, client: Client) async -> Data? {
    guard let url, !url.isEmpty, let source = try? MediaSource.fromUrl(url: url) else {
      return nil
    }
    return try? await withTimeout(avatarTimeout) {
      try await client.getMediaThumbnail(
        mediaSource: source, width: avatarSize, height: avatarSize)
    }
  }

  static func isWorthRetrying(_ status: NotificationStatus?) -> Bool {
    switch status {
    case nil, .eventNotFound: return true
    case .eventFilteredOut, .eventRedacted: return false
    case .event(let item):
      guard case .timeline(let event) = item.event else { return false }
      if case .messageLike(.roomEncrypted)? = try? event.content() { return true }
      return false
    }
  }

  static func outcome(of status: NotificationStatus?, ownUserId: String? = nil)
    -> NotificationOutcome
  {
    guard let status else { return .generic }
    guard case .event(let item) = status else {
      return Self.outcome(withoutEvent: status) ?? .generic
    }
    let sender = item.senderInfo.displayName.flatMap { $0.isEmpty ? nil : $0 }
    switch item.event {
    case .invite(let senderId):
      return .show(
        Self.content(
          senderId: senderId, sender: sender ?? senderId, room: item.roomInfo.displayName,
          isDirect: item.roomInfo.isDirect, body: "Invited you to chat"))
    case .timeline(let event):
      let senderId = event.senderId()
      if Self.isOwn(senderId: senderId, ownUserId: ownUserId) { return .hide }
      guard case .messageLike(let content)? = try? event.content() else { return .generic }
      if Self.isSilent(content, rawEvent: item.rawEvent) { return .hide }
      guard let body = Self.body(of: content) else { return .generic }
      return .show(
        Self.content(
          senderId: senderId, sender: sender ?? senderId, room: item.roomInfo.displayName,
          isDirect: item.roomInfo.isDirect, body: body,
          threadId: Self.threadId(item.threadId, rawEvent: item.rawEvent), isMessage: true))
    }
  }

  static func outcome(withoutEvent status: NotificationStatus) -> NotificationOutcome? {
    switch status {
    case .event: nil
    case .eventFilteredOut, .eventRedacted: .hide
    case .eventNotFound: .generic
    }
  }

  static func isSilent(_ content: MessageLikeEventContent, rawEvent: String) -> Bool {
    switch content {
    case .reactionContent, .roomRedaction: true
    case .roomMessage: isEdit(rawEvent: rawEvent)
    default: false
    }
  }

  static func isEdit(rawEvent: String) -> Bool {
    relation(rawEvent: rawEvent)?["rel_type"] as? String == "m.replace"
  }

  static func isOwn(senderId: String, ownUserId: String?) -> Bool {
    guard let ownUserId, !ownUserId.isEmpty else { return false }
    return senderId == ownUserId
  }

  static func threadId(_ sdkThreadId: String?, rawEvent: String) -> String? {
    if let sdkThreadId, !sdkThreadId.isEmpty { return sdkThreadId }
    guard let relation = relation(rawEvent: rawEvent),
      relation["rel_type"] as? String == "m.thread",
      let root = relation["event_id"] as? String, !root.isEmpty
    else { return nil }
    return root
  }

  private static func relation(rawEvent: String) -> [String: Any]? {
    guard
      let event = try? JSONSerialization.jsonObject(with: Data(rawEvent.utf8)) as? [String: Any],
      let content = event["content"] as? [String: Any]
    else { return nil }
    return content["m.relates_to"] as? [String: Any]
  }

  static func content(
    senderId: String = "", sender: String, room: String, isDirect: Bool, body: String,
    threadId: String? = nil, isMessage: Bool = false
  ) -> NotificationContent {
    NotificationContent(
      title: isDirect ? sender : room, subtitle: isDirect ? "" : sender, body: body,
      senderId: senderId, senderName: sender, roomName: room, isDirect: isDirect,
      threadId: threadId, isMessage: isMessage)
  }

  static func body(of content: MessageLikeEventContent) -> String? {
    switch content {
    case .roomMessage(let type, _): body(of: type)
    case .poll(let question): "📊 \(question)"
    case .sticker: "Sent a sticker"
    default: nil
    }
  }

  static func body(of type: MessageType) -> String {
    switch type {
    case .text(let content): content.body
    case .emote(let content): "* \(content.body)"
    case .notice(let content): content.body
    case .image: "📷 Photo"
    case .video: "🎥 Video"
    case .audio: "🎤 Audio"
    case .file(let content): "📎 \(content.filename)"
    case .gallery: "🖼️ Photos"
    case .location: "📍 Location"
    case .other(_, let body): body
    }
  }
}
