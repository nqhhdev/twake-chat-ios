import SwiftUI

/// One colour with a light and a dark value, stored as the 0xAARRGGBB numbers of linagora-design-flutter.
///
/// Use it anywhere SwiftUI takes a `ShapeStyle` (`foregroundStyle`, `background`, `fill`, `tint`): it resolves to
/// `light` or `dark` from the environment's colour scheme.
public struct ColorToken: ShapeStyle, Hashable, Sendable {
  public let light: UInt32
  public let dark: UInt32

  /// A missing `dark` falls back to `light`, as the `…Dark` getters of `LinagoraSysColors` do.
  public init(_ light: UInt32, dark: UInt32? = nil) {
    self.light = light
    self.dark = dark ?? light
  }

  public func argb(for scheme: ColorScheme) -> UInt32 {
    scheme == .dark ? dark : light
  }

  public func color(for scheme: ColorScheme) -> Color {
    Color(argb: argb(for: scheme))
  }

  public func resolve(in environment: EnvironmentValues) -> Color {
    color(for: environment.colorScheme)
  }
}

extension Color {
  /// A colour from a 0xAARRGGBB number, as Flutter's `Color(0xFF0A84FF)` reads it.
  public init(argb: UInt32) {
    self.init(
      .sRGB,
      red: Double((argb >> 16) & 0xFF) / 255,
      green: Double((argb >> 8) & 0xFF) / 255,
      blue: Double(argb & 0xFF) / 255,
      opacity: Double((argb >> 24) & 0xFF) / 255
    )
  }
}
