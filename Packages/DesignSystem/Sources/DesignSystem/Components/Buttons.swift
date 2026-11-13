import SwiftUI

/// Corner radii of twake-on-matrix `AppConfig.borderRadius` (20) and the half of it that `themes.dart` uses for
/// text fields, text and outlined buttons and dialogs.
public enum TwakeRadius {
  public static let large: CGFloat = 20
  public static let small: CGFloat = 10
}

/// The filled button of `themes.dart` `elevatedButtonTheme`: 16 pt padding, 16 pt label, corner radius 20,
/// filled with `primary` and labelled in `onPrimary`.
public struct TwakePrimaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .textStyle(TextStyles.labelLarge.with(size: 16))
      .foregroundStyle(SysColors.onPrimary)
      .padding(16)
      .frame(maxWidth: .infinity)
      .background(SysColors.primary, in: RoundedRectangle(cornerRadius: TwakeRadius.large))
      .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.38)
  }
}

/// The outlined and text buttons of `themes.dart` (`outlinedButtonTheme`, `textButtonTheme`): corner radius 10,
/// label in `primary`, with an `outline` border when outlined.
public struct TwakeSecondaryButtonStyle: ButtonStyle {
  public enum Variant: Sendable {
    case outlined
    case text
  }

  @Environment(\.isEnabled) private var isEnabled
  private let variant: Variant

  public init(_ variant: Variant = .outlined) {
    self.variant = variant
  }

  public func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(cornerRadius: TwakeRadius.small)
    return configuration.label
      .textStyle(TextStyles.labelLarge)
      .foregroundStyle(SysColors.primary)
      .padding(.horizontal, variant == .outlined ? 24 : 12)
      .frame(minHeight: 40)
      .contentShape(shape)
      .overlay {
        if variant == .outlined {
          shape.strokeBorder(SysColors.outline, lineWidth: 1)
        }
      }
      .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.38)
  }
}

extension ButtonStyle where Self == TwakePrimaryButtonStyle {
  public static var twakePrimary: TwakePrimaryButtonStyle { TwakePrimaryButtonStyle() }
}

extension ButtonStyle where Self == TwakeSecondaryButtonStyle {
  public static var twakeSecondary: TwakeSecondaryButtonStyle {
    TwakeSecondaryButtonStyle(.outlined)
  }
  public static var twakeText: TwakeSecondaryButtonStyle { TwakeSecondaryButtonStyle(.text) }
}

#Preview("Buttons, light") {
  ButtonsPreview().preferredColorScheme(.light)
}

#Preview("Buttons, dark") {
  ButtonsPreview().preferredColorScheme(.dark)
}

private struct ButtonsPreview: View {
  var body: some View {
    VStack(spacing: 16) {
      Button("Sign in") {}.buttonStyle(.twakePrimary)
      Button("Sign in") {}.buttonStyle(.twakePrimary).disabled(true)
      Button("Use another server") {}.buttonStyle(.twakeSecondary)
      Button("Cancel") {}.buttonStyle(.twakeText)
    }
    .padding()
    .background(SysColors.background)
  }
}
