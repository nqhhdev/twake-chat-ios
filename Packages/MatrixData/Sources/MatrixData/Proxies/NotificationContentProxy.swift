import Domain
import Foundation
import MatrixRustSDK

/// `NotificationContentRepository` on the SDK's notification client (ADR 0009): restores the saved session in the
/// extension's process on the shared store with its own cross-process lock name (ADR 0007), then asks the notification
/// client for the event, which fetches and decrypts it. Nothing here logs: the content is the user's message.
public actor NotificationContentProxy: NotificationContentRepository {
  private let authentication: MatrixAuthenticationRepository

  /// - Parameter authentication: Built on the shared store and Keychain group with the lock holder name `"nse"`.
  public init(authentication: MatrixAuthenticationRepository) {
    self.authentication = authentication
  }

  public func content(roomId: String, eventId: String) async -> NotificationContent? {
    guard (try? await authentication.restoreSession()) != nil,
      let client = await authentication.clientProxy?.client,
      let notifications = try? await client.notificationClient(processSetup: .multipleProcesses),
      case .event(let item)? = try? await notifications.getNotification(
        roomId: roomId, eventId: eventId)
    else { return nil }
    let sender = item.senderInfo.displayName.flatMap { $0.isEmpty ? nil : $0 }
    switch item.event {
    case .invite(let senderId):
      return Self.content(
        sender: sender ?? senderId, room: item.roomInfo.displayName,
        isDirect: item.roomInfo.isDirect, body: "Invited you to chat")
    case .timeline(let event):
      guard case .messageLike(let content)? = try? event.content(),
        let body = Self.body(of: content)
      else { return nil }
      return Self.content(
        sender: sender ?? event.senderId(), room: item.roomInfo.displayName,
        isDirect: item.roomInfo.isDirect, body: body)
    }
  }

  /// A direct chat is titled with the sender, as Messages does; a group with the room, and the sender below.
  static func content(sender: String, room: String, isDirect: Bool, body: String)
    -> NotificationContent
  {
    isDirect
      ? NotificationContent(title: sender, subtitle: "", body: body)
      : NotificationContent(title: room, subtitle: sender, body: body)
  }

  /// The text of a message, or a short description of what was sent; `nil` for what does not notify (or could not be
  /// decrypted), so the generic text stays.
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
