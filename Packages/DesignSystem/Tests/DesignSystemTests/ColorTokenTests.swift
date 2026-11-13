import DesignSystem
import SwiftUI
import Testing

/// Expected values are read from linagora-design-flutter v0.4.2 `lib/colors/linagora_sys_colors.dart` and
/// `linagora_ref_colors.dart`.
struct ColorTokenTests {
  @Test func lightValuesMatchLinagoraSysColors() {
    #expect(SysColors.primary.light == 0xFF0A_84FF)
    #expect(SysColors.onPrimary.light == 0xFFFF_FFFF)
    #expect(SysColors.surface.light == 0xFFF4_F4F4)
    #expect(SysColors.error.light == 0xFFFF_3347)
    #expect(SysColors.textSecondary.light == 0xFF5C_6268)
    #expect(SysColors.outline.light == 0xFFAE_AEC0)
  }

  @Test func darkValuesMatchLinagoraSysColors() {
    #expect(SysColors.primaryContainer.dark == 0xFF2D_2D2E)
    #expect(SysColors.onBackground.dark == 0xFFE6_E1E5)
    #expect(SysColors.error.dark == 0xFFE6_4646)
    #expect(SysColors.outline.dark == 0xFF52_5256)
  }

  @Test func tokenWithoutDarkValueFallsBackToLight() {
    #expect(SysColors.success.dark == 0xFF00_AD48)
    #expect(SysColors.textSecondary.dark == SysColors.textSecondary.light)
    #expect(ColorToken(0xFF12_3456).dark == 0xFF12_3456)
  }

  @Test func tokenPicksTheValueOfTheColourScheme() {
    #expect(SysColors.primaryContainer.argb(for: .light) == 0xFFD2_E9FF)
    #expect(SysColors.primaryContainer.argb(for: .dark) == 0xFF2D_2D2E)
  }

  @Test func refPaletteTones() {
    #expect(RefColors.neutralVariant[tone: 60]?.light == 0xFF93_8F99)
    #expect(RefColors.primary[tone: 40]?.light == 0xFF0A_84FF)
    #expect(RefColors.tertiary[tone: 80]?.light == 0xFFEE_F6FE)
    #expect(RefColors.neutral[tone: 55] == nil)
  }

  @Test func colourFromArgbSplitsTheChannels() {
    let resolved = Color(argb: 0x800A_84FF).resolve(in: EnvironmentValues())
    #expect(abs(Double(resolved.red) - 10.0 / 255) < 0.01)
    #expect(abs(Double(resolved.green) - 132.0 / 255) < 0.01)
    #expect(abs(Double(resolved.blue) - 1) < 0.01)
    #expect(abs(Double(resolved.opacity) - 128.0 / 255) < 0.01)
  }
}
