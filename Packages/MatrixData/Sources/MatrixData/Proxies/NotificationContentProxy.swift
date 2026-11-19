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

  public func content(roomId: String, eventId: String) async -> NotificationOutcome {
    guard (try? await authentication.restoreSession()) != nil,
      let client = await authentication.clientProxy?.client,
      let notifications = try? await client.notificationClient(processSetup: .multipleProcesses),
      let status = try? await notifications.getNotification(roomId: roomId, eventId: eventId)
    else { return .generic }
    guard case .event(let item) = status else {
      return Self.outcome(withoutEvent: status) ?? .generic
    }
    let sender = item.senderInfo.displayName.flatMap { $0.isEmpty ? nil : $0 }
    switch item.event {
    case .invite(let senderId):
      return .show(
        Self.content(
          sender: sender ?? senderId, room: item.roomInfo.displayName,
          isDirect: item.roomInfo.isDirect, body: "Invited you to chat"))
    case .timeline(let event):
      guard case .messageLike(let content)? = try? event.content() else { return .generic }
      if Self.isSilent(content, rawEvent: item.rawEvent) { return .hide }
      guard let body = Self.body(of: content) else { return .generic }
      return .show(
        Self.content(
          sender: sender ?? event.senderId(), room: item.roomInfo.displayName,
          isDirect: item.roomInfo.isDirect, body: body))
    }
  }

  /// A status without an event: hidden when the SDK says the event must not notify (the user's push rules, an ignored
  /// sender) or was deleted; the generic text when it was not found, as for any other failure (ADR 0009). `nil` for a
  /// found event, which `content(roomId:eventId:)` reads.
  static func outcome(withoutEvent status: NotificationStatus) -> NotificationOutcome? {
    switch status {
    case .event: nil
    case .eventFilteredOut, .eventRedacted: .hide
    case .eventNotFound: .generic
    }
  }

  /// Events that never notify: a reaction, a redaction, and an edit of an earlier message (`m.replace`), which the
  /// homeserver may still push in an encrypted room.
  static func isSilent(_ content: MessageLikeEventContent, rawEvent: String) -> Bool {
    switch content {
    case .reactionContent, .roomRedaction: true
    case .roomMessage: isEdit(rawEvent: rawEvent)
    default: false
    }
  }

  /// Whether the event's JSON relates it to an earlier event as a replacement. The relation stays in clear in an
  /// encrypted event, so this holds whether or not the SDK hands back the decrypted JSON.
  static func isEdit(rawEvent: String) -> Bool {
    guard
      let event = try? JSONSerialization.jsonObject(with: Data(rawEvent.utf8)) as? [String: Any],
      let content = event["content"] as? [String: Any],
      let relation = content["m.relates_to"] as? [String: Any]
    else { return false }
    return relation["rel_type"] as? String == "m.replace"
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
