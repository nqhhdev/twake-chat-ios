/// The line that says who is typing, as the chat screen and the chat list write it (web `LiveStatus`, Flutter
/// `chat_list_item_title.dart`).
public enum TypingText {
  /// `nil` when nobody types; otherwise "Alice is typing…", "Alice and Bob are typing…" or "Alice and 2 others are
  /// typing…".
  public static func line(for names: [String]) -> String? {
    switch names.count {
    case 0: nil
    case 1: localized("\(names[0]) is typing…")
    case 2: localized("\(names[0]) and \(names[1]) are typing…")
    default: localized("\(names[0]) and \(names.count - 1) others are typing…")
    }
  }
}
