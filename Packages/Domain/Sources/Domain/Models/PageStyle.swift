import Foundation

/// How a room's page looks, as the web client writes it in the state `app.twake.chat.page_style`, key `''`
/// (`{ "cover_url"?: "mxc://…", "accent_color"?: "#rrggbb" }`, web D90 and D350): a cover picture and an accent
/// colour, drawn behind white text. Read only here; the web changes it from the room's « Edit ».
public struct PageStyle: Sendable, Equatable {
  public static let stateEventType = "app.twake.chat.page_style"

  /// The cover picture.
  public let cover: MediaReference?
  /// The accent colour, `#rrggbb` in lowercase.
  public let accentColor: String?

  public init(cover: MediaReference?, accentColor: String?) {
    self.cover = cover
    self.accentColor = accentColor
  }

  /// The style of a state event's content, or `nil` when it gives nothing to draw. As the web reads it, a field that
  /// is not a string is left out; here a cover that is not an `mxc://` URI and a colour that is not `#rrggbb` are left
  /// out too, since neither could be drawn. `cover` turns the `mxc://` URI into a picture to load.
  public init?(content: [String: Any], cover: (String) -> MediaReference?) {
    let coverURL = (content["cover_url"] as? String).flatMap { $0.hasPrefix("mxc://") ? $0 : nil }
    let accent = (content["accent_color"] as? String).flatMap(Self.hexColor)
    let picture = coverURL.flatMap(cover)
    guard picture != nil || accent != nil else { return nil }
    self.init(cover: picture, accentColor: accent)
  }

  /// The red, green and blue of the accent colour, each from 0 to 1.
  public var accentRGB: (red: Double, green: Double, blue: Double)? {
    guard let accentColor, let value = UInt32(accentColor.dropFirst(), radix: 16) else {
      return nil
    }
    return (
      Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255,
      Double(value & 0xFF) / 255
    )
  }

  /// `#rrggbb` in lowercase, or `nil` for any other text.
  static func hexColor(_ text: String) -> String? {
    let digits = text.dropFirst()
    guard text.first == "#", digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
    return text.lowercased()
  }
}
