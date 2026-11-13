import SwiftUI

/// A round avatar with the first letter of a name, as twake-on-matrix `Avatar` shows it before a picture loads. The
/// colour is picked from the name, so one person keeps one colour. The Flutter app draws a gradient from
/// linagora-design-flutter's `avatarColors`; those colours are not copied yet, so this uses the Twake reference tones.
public struct TwakeAvatar: View {
  private let name: String
  private let size: CGFloat

  public init(name: String, size: CGFloat = 48) {
    self.name = name
    self.size = size
  }

  public var body: some View {
    Text(Self.initial(of: name))
      .font(.custom(TextStyleToken.Weight.semibold.face, size: size * 0.42))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(Self.color(for: name), in: Circle())
      .accessibilityHidden(true)
  }

  /// The first letter or digit of the name, upper-cased; a Matrix id's sigil is skipped.
  static func initial(of name: String) -> String {
    let letter = name.first { $0.isLetter || $0.isNumber }
    return letter.map { String($0).uppercased() } ?? "#"
  }

  static let palette: [ColorToken] = [
    RefColors.primary[tone: 40], RefColors.secondary[tone: 40], RefColors.tertiary[tone: 40],
    RefColors.primary[tone: 60], RefColors.secondary[tone: 60], RefColors.tertiary[tone: 60],
  ].compactMap { $0 }

  /// A stable colour for the name: the same name always gets the same colour, across launches.
  static func color(for name: String) -> ColorToken {
    let sum = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
    return palette[sum % palette.count]
  }
}

#Preview("Avatars") {
  HStack {
    TwakeAvatar(name: "Alice")
    TwakeAvatar(name: "@bob:example.org")
    TwakeAvatar(name: "Charlie", size: 32)
  }
  .padding()
}
