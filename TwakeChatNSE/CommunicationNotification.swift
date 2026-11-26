import Domain
import Foundation
import Intents
@preconcurrency import UserNotifications

enum CommunicationNotification {
  static func intent(for found: NotificationContent, roomId: String, accountUserId: String?)
    -> INSendMessageIntent
  {
    let sender = INPerson(
      personHandle: INPersonHandle(value: found.senderId, type: .unknown), nameComponents: nil,
      displayName: found.senderName, image: found.senderAvatar.map { INImage(imageData: $0) },
      contactIdentifier: nil, customIdentifier: found.senderId)
    let me = INPerson(
      personHandle: INPersonHandle(value: nil, type: .unknown), nameComponents: nil,
      displayName: nil, image: nil, contactIdentifier: nil, customIdentifier: accountUserId,
      isMe: true)
    let intent = INSendMessageIntent(
      recipients: found.isDirect ? nil : [me, sender], outgoingMessageType: .outgoingMessageText,
      content: found.body,
      speakableGroupName: found.isDirect ? nil : INSpeakableString(spokenPhrase: found.roomName),
      conversationIdentifier: roomId, serviceName: nil, sender: sender, attachments: nil)
    if !found.isDirect, let avatar = found.roomAvatar {
      intent.setImage(INImage(imageData: avatar), forParameterNamed: \.speakableGroupName)
    }
    return intent
  }

  static func content(_ content: UNMutableNotificationContent, intent: INSendMessageIntent) async
    -> UNMutableNotificationContent?
  {
    let interaction = INInteraction(intent: intent, response: nil)
    interaction.direction = .incoming
    try? await interaction.donate()
    guard let updated = try? content.updating(from: intent) else { return nil }
    return updated.mutableCopy() as? UNMutableNotificationContent
  }
}
