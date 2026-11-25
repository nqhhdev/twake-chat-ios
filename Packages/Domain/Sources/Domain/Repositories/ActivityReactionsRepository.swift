/// The reactions of other people on the user's messages, for the Activity (web D58). As on the web, they come from the
/// history this device already holds (main timeline and threads), so nothing more is asked of the server and a reaction
/// on a message out of that history is not listed.
public protocol ActivityReactionsRepository: Sendable {
  /// The reactions on the user's messages in these rooms, newest first, at most `ActivityReactions.limit`. A room that
  /// is not joined here, or holds nothing yet, adds nothing.
  func reactions(inRooms roomIds: [String]) async -> [ActivityReaction]
}
