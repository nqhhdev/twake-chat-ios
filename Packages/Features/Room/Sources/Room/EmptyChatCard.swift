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
        title: "Channel “\(roomName)” is created",
        description:
          "A broadcast channel shares news with its followers. Only the owner and moderators post in it; "
          + "followers read the messages.",
        points: [])
    }
    guard canPost else {
      return EmptyChatCard(title: "No message here yet", description: nil, points: [])
    }
    if isDirect {
      return EmptyChatCard(
        title: "No message here yet", description: "Send a message to start the conversation",
        points: isEncrypted ? ["End-to-end encrypted messages"] : [])
    }
    return EmptyChatCard(
      title: "Congratulations on your new chat!", description: nil,
      points: ["Up to 100,000 members", "Persistent chat history"]
        + (isEncrypted ? ["End-to-end encrypted messages"] : [])
        + ["Admins with different rights"])
  }
}
