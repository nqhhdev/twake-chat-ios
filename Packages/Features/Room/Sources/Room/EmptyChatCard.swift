import Foundation

/// What a chat with no message yet shows in place of the timeline.
///
/// Wording: the Flutter app's cards (`DraftChatEmpty`, `GroupChatEmptyView`); the web client's for a Broadcast and for
/// the encryption and admin lines (`header.congrats*`, `chat.channelCreated`, `chat.broadcastExplainer`).
public struct EmptyChatCard: Equatable, Sendable {
  public let title: String
  /// A line under the title.
  public let description: String?
  /// What the new chat offers, one line each.
  public let points: [String]

  /// - A Broadcast says what it is, to its owner and to a reader.
  /// - Someone who may not post is not invited to write.
  /// - A direct chat invites a first message.
  /// - A group lists what it offers; encryption only where the room has it.
  public static func card(
    roomName: String, isDirect: Bool, isBroadcast: Bool, isEncrypted: Bool, canPost: Bool
  ) -> EmptyChatCard {
    if isBroadcast {
      return EmptyChatCard(
        title: localized("Channel “\(roomName)” is created"),
        description:
          localized(
            "A broadcast channel shares news with its followers. Only the owner and moderators post in it; followers read the messages."
          ),
        points: [])
    }
    guard canPost else {
      return EmptyChatCard(title: localized("No message here yet"), description: nil, points: [])
    }
    if isDirect {
      return EmptyChatCard(
        title: localized("No message here yet"),
        description: localized("Send a message to start the conversation"),
        points: isEncrypted ? [localized("End-to-end encrypted messages")] : [])
    }
    return EmptyChatCard(
      title: localized("Congratulations on your new chat!"), description: nil,
      points: [localized("Up to 100,000 members"), localized("Persistent chat history")]
        + (isEncrypted ? [localized("End-to-end encrypted messages")] : [])
        + [localized("Admins with different rights")])
  }
}
