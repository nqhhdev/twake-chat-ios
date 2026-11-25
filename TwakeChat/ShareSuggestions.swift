import Domain
import Intents
import Observation
import Room

@MainActor
final class ShareSuggestions {
  struct System {
    var donate: @MainActor (INInteraction) -> Void
    var forget: @MainActor (String) -> Void
    var forgetAll: @MainActor () -> Void

    static let live = System(
      donate: { $0.donate(completion: nil) },
      forget: { INInteraction.delete(with: $0, completion: nil) },
      forgetAll: { INInteraction.deleteAll(completion: nil) })
  }

  static let avatarSize = 96

  private let system: System
  private var avatars: [MediaReference: Data] = [:]

  init(system: System = .live) {
    self.system = system
  }

  func follow(_ room: RoomViewModel) {
    withObservationTracking {
      _ = room.sendCount
    } onChange: { [weak self, weak room] in
      Task { @MainActor in
        guard let self, let room else { return }
        self.follow(room)
        await self.suggest(
          roomId: room.roomId, name: room.roomName, avatar: room.roomAvatar, media: room.media)
      }
    }
  }

  func suggest(
    roomId: String, name: String, avatar: MediaReference?, media: any MediaRepository
  ) async {
    let image = await avatarData(avatar, media: media).map { INImage(imageData: $0) }
    let interaction = INInteraction(
      intent: Self.intent(roomId: roomId, name: name, image: image), response: nil)
    interaction.direction = .outgoing
    interaction.groupIdentifier = roomId
    system.donate(interaction)
  }

  func forget(_ roomId: String) {
    system.forget(roomId)
  }

  func forgetAll() {
    avatars = [:]
    system.forgetAll()
  }

  static func intent(roomId: String, name: String, image: INImage?) -> INSendMessageIntent {
    let intent = INSendMessageIntent(
      recipients: nil, outgoingMessageType: .outgoingMessageText, content: nil,
      speakableGroupName: INSpeakableString(spokenPhrase: name), conversationIdentifier: roomId,
      serviceName: nil, sender: nil, attachments: nil)
    if let image {
      intent.setImage(image, forParameterNamed: \.speakableGroupName)
    }
    return intent
  }

  private func avatarData(_ avatar: MediaReference?, media: any MediaRepository) async -> Data? {
    guard let avatar else { return nil }
    if let cached = avatars[avatar] { return cached }
    guard
      let data = try? await media.thumbnail(
        avatar, width: Self.avatarSize, height: Self.avatarSize)
    else { return nil }
    avatars[avatar] = data
    return data
  }
}
