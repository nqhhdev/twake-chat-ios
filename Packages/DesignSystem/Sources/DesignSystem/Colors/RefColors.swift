import SwiftUI

/// A tonal palette of `LinagoraRefColors`: tones 0, 10, 20 … 90, 95, 99, 100, plus the base swatch value.
public struct TonalPalette: Hashable, Sendable {
  public let base: UInt32
  public let tones: [Int: UInt32]

  /// The tone as a token with the same value in light and dark mode, or nil when the palette has no such tone.
  public subscript(tone tone: Int) -> ColorToken? {
    tones[tone].map { ColorToken($0) }
  }
}

/// The reference palettes of `LinagoraRefColors.material()` in linagora-design-flutter v0.4.2.
/// Values are copied by hand from `lib/colors/linagora_ref_colors.dart`. They have no dark variant.
public enum RefColors {
  public static let primary = TonalPalette(
    base: 0xFF46_A2FF,
    tones: [
      0: 0xFF00_0000, 10: 0xFF01_57AD, 20: 0xFF00_6BD8, 30: 0xFF00_7CF9, 40: 0xFF0A_84FF,
      50: 0xFF46_A2FF, 60: 0xFF7B_BDFF, 70: 0xFFAA_D4FE, 80: 0xFFBF_DFFF, 90: 0xFFD2_E9FF,
      95: 0xFFE3_F1FF, 99: 0xFFF7_FBFF, 100: 0xFFFF_FFFF,
    ]
  )

  public static let secondary = TonalPalette(
    base: 0xFF85_B5EC,
    tones: [
      0: 0xFF00_0000, 10: 0xFF24_3B55, 20: 0xFF43_6E9F, 30: 0xFF50_85C4, 40: 0xFF5C_9CE6,
      50: 0xFF85_B5EC, 60: 0xFF96_BCE8, 70: 0xFFB5_D1F1, 80: 0xFFD1_E0F2, 90: 0xFFE8_F0FA,
      95: 0xFFF1_F5FA, 99: 0xFFFF_FBFE, 100: 0xFFFF_FFFF,
    ]
  )

  public static let tertiary = TonalPalette(
    base: 0xFFCF_D8E2,
    tones: [
      0: 0xFF00_0000, 10: 0xFF37_383A, 20: 0xFF71_767C, 30: 0xFF99_A0A9, 40: 0xFFB8_C1CC,
      50: 0xFFCF_D8E2, 60: 0xFFD8_E1EB, 70: 0xFFE5_ECF3, 80: 0xFFEE_F6FE, 90: 0xFFFC_FCFC,
      95: 0xFFFF_FFFF, 99: 0xFFFF_FBFA, 100: 0xFFFF_FFFF,
    ]
  )

  public static let neutral = TonalPalette(
    base: 0xFF78_7579,
    tones: [
      0: 0xFF00_0000, 10: 0xFF1C_1B1F, 20: 0xFF31_3033, 30: 0xFF48_4649, 40: 0xFF60_5D62,
      50: 0xFF78_7579, 60: 0xFF93_9094, 70: 0xFFAE_AAAE, 80: 0xFFC9_C5CA, 90: 0xFFE6_E1E5,
      95: 0xFFF4_EFF4, 99: 0xFFFF_FBFE, 100: 0xFFFF_FFFF,
    ]
  )

  public static let neutralVariant = TonalPalette(
    base: 0xFF79_747E,
    tones: [
      0: 0xFF00_0000, 10: 0xFF1D_1A22, 20: 0xFF32_2F37, 30: 0xFF49_454F, 40: 0xFF60_5D66,
      50: 0xFF79_747E, 60: 0xFF93_8F99, 70: 0xFFAE_A9B4, 80: 0xFFCA_C4D0, 90: 0xFFE7_E0EC,
      95: 0xFFF5_EEFA, 99: 0xFFFF_FBFE, 100: 0xFFFF_FFFF,
    ]
  )

  /// The base value 0xFF46A2FF is what the Flutter source declares for this swatch, copied as is.
  public static let error = TonalPalette(
    base: 0xFF46_A2FF,
    tones: [
      0: 0xFF00_0000, 10: 0xFF7A_1E27, 20: 0xFFB5_2C39, 30: 0xFFD3_2C3C, 40: 0xFFFF_3347,
      50: 0xFFFF_4D5E, 60: 0xFFFF_7A87, 70: 0xFFFF_939D, 80: 0xFFFF_B4BB, 90: 0xFFFF_D2D7,
      95: 0xFFFC_EEEE, 99: 0xFFFF_FBF9, 100: 0xFFFF_FFFF,
    ]
  )
}
