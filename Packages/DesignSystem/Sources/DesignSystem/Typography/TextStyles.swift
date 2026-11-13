import SwiftUI

/// One text style of `LinagoraTextStyle`, kept as plain numbers: size, line height in points, weight and letter
/// spacing. Flutter writes the line height as a ratio (`height: 64 / 57`); here it is the 64.
public struct TextStyleToken: Hashable, Sendable {
  public enum Weight: Int, Sendable {
    case regular = 400
    case medium = 500
    case semibold = 600
    case bold = 700

    /// The PostScript name of the bundled TwakeInter face for this weight.
    public var face: String {
      switch self {
      case .regular: "TwakeInter-Regular"
      case .medium: "TwakeInter-Medium"
      case .semibold: "TwakeInter-SemiBold"
      case .bold: "TwakeInter-Bold"
      }
    }
  }

  public let size: CGFloat
  public let lineHeight: CGFloat
  public let weight: Weight
  public let letterSpacing: CGFloat

  public init(size: CGFloat, lineHeight: CGFloat, weight: Weight, letterSpacing: CGFloat) {
    self.size = size
    self.lineHeight = lineHeight
    self.weight = weight
    self.letterSpacing = letterSpacing
  }

  /// The same style at another size, as Flutter's `TextStyle.merge(TextStyle(fontSize: …))` does.
  public func with(size: CGFloat) -> TextStyleToken {
    TextStyleToken(size: size, lineHeight: lineHeight, weight: weight, letterSpacing: letterSpacing)
  }

  /// SwiftUI adds line spacing between lines: (height ratio − 1) × size, which is line height − size.
  public var lineSpacing: CGFloat { lineHeight - size }

  public var font: Font {
    TwakeInter.register()
    return Font.custom(weight.face, size: size)
  }
}

/// The 24 text styles of linagora-design-flutter v0.4.2: the 15 Material slots of `LinagoraTextTheme` and the 9 of
/// `LinagoraTextThemeExtension`, all in TwakeInter. Copied by hand from `lib/style/linagora_text_style.dart`.
public enum TextStyles {
  public static let displayLarge = TextStyleToken(
    size: 57, lineHeight: 64, weight: .bold, letterSpacing: 0)
  public static let displayMedium = TextStyleToken(
    size: 45, lineHeight: 52, weight: .semibold, letterSpacing: 0)
  public static let displaySmall = TextStyleToken(
    size: 36, lineHeight: 44, weight: .semibold, letterSpacing: 0)
  public static let headlineLarge = TextStyleToken(
    size: 32, lineHeight: 40, weight: .semibold, letterSpacing: 0)
  public static let headlineMedium = TextStyleToken(
    size: 28, lineHeight: 36, weight: .semibold, letterSpacing: 0)
  public static let headlineSmall = TextStyleToken(
    size: 24, lineHeight: 32, weight: .semibold, letterSpacing: 0)
  public static let titleLarge = TextStyleToken(
    size: 22, lineHeight: 28, weight: .semibold, letterSpacing: 0)
  public static let titleMedium = TextStyleToken(
    size: 16, lineHeight: 24, weight: .medium, letterSpacing: 0.15)
  public static let titleSmall = TextStyleToken(
    size: 14, lineHeight: 20, weight: .medium, letterSpacing: 0.1)
  public static let labelLarge = TextStyleToken(
    size: 14, lineHeight: 20, weight: .medium, letterSpacing: 0.1)
  public static let labelMedium = TextStyleToken(
    size: 12, lineHeight: 16, weight: .medium, letterSpacing: 0.5)
  public static let labelSmall = TextStyleToken(
    size: 11, lineHeight: 16, weight: .medium, letterSpacing: 0.5)
  public static let bodyLarge = TextStyleToken(
    size: 17, lineHeight: 24, weight: .medium, letterSpacing: -0.15)
  public static let bodyMedium = TextStyleToken(
    size: 14, lineHeight: 20, weight: .medium, letterSpacing: 0.25)
  public static let bodySmall = TextStyleToken(
    size: 12, lineHeight: 16, weight: .medium, letterSpacing: 0.4)

  // LinagoraTextThemeExtension
  public static let titleSemibold = TextStyleToken(
    size: 16, lineHeight: 24, weight: .semibold, letterSpacing: 0.15)
  public static let titleSmall2 = TextStyleToken(
    size: 15, lineHeight: 20, weight: .medium, letterSpacing: 0.1)
  public static let bodyLargeBold = TextStyleToken(
    size: 17, lineHeight: 24, weight: .bold, letterSpacing: -0.15)
  public static let bodyLarge1 = TextStyleToken(
    size: 17, lineHeight: 24, weight: .semibold, letterSpacing: -0.15)
  public static let bodyLarge2 = TextStyleToken(
    size: 17, lineHeight: 24, weight: .regular, letterSpacing: -0.15)
  public static let bodyMedium1 = TextStyleToken(
    size: 16, lineHeight: 24, weight: .regular, letterSpacing: -0.15)
  public static let bodyMedium2 = TextStyleToken(
    size: 14, lineHeight: 20, weight: .semibold, letterSpacing: 0.25)
  public static let bodyMedium3 = TextStyleToken(
    size: 14, lineHeight: 20, weight: .regular, letterSpacing: 0.25)
  public static let bodyMedium4 = TextStyleToken(
    size: 15, lineHeight: 20, weight: .regular, letterSpacing: -0.15)
}

extension View {
  /// Applies a TwakeInter style: font, letter spacing and line spacing.
  public func textStyle(_ style: TextStyleToken) -> some View {
    font(style.font)
      .tracking(style.letterSpacing)
      .lineSpacing(style.lineSpacing)
  }
}
