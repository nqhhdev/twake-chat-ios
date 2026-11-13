/// One kind of message a timeline can be limited to: the chat details tabs (pictures and videos, files, messages with
/// a link, as the Flutter chat details) and text messages, which the search of an encrypted chat reads.
public enum RoomContentKind: String, Sendable, Identifiable {
  case media
  case files
  case links
  case text

  /// The chat details tabs, in order.
  public static let tabs: [RoomContentKind] = [.media, .files, .links]

  public var id: String { rawValue }
}
