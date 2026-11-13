import CoreText
import DesignSystem
import Testing

/// Expected values are read from linagora-design-flutter v0.4.2 `lib/style/linagora_text_style.dart`.
struct TextStyleTests {
  @Test func displayLarge() {
    #expect(
      TextStyles.displayLarge
        == TextStyleToken(size: 57, lineHeight: 64, weight: .bold, letterSpacing: 0))
  }

  @Test func titleLarge() {
    #expect(
      TextStyles.titleLarge
        == TextStyleToken(size: 22, lineHeight: 28, weight: .semibold, letterSpacing: 0))
  }

  @Test func bodyMedium() {
    #expect(
      TextStyles.bodyMedium
        == TextStyleToken(size: 14, lineHeight: 20, weight: .medium, letterSpacing: 0.25))
  }

  @Test func bodyMedium4FromTheExtension() {
    #expect(
      TextStyles.bodyMedium4
        == TextStyleToken(size: 15, lineHeight: 20, weight: .regular, letterSpacing: -0.15))
  }

  @Test func lineSpacingIsLineHeightMinusSize() {
    #expect(TextStyles.displayLarge.lineSpacing == 7)
    #expect(TextStyles.bodyLarge.lineSpacing == 7)
  }

  @Test func weightsMapToTheTwakeInterFaces() {
    #expect(TextStyleToken.Weight.regular.face == "TwakeInter-Regular")
    #expect(TextStyleToken.Weight.medium.face == "TwakeInter-Medium")
    #expect(TextStyleToken.Weight.semibold.face == "TwakeInter-SemiBold")
    #expect(TextStyleToken.Weight.bold.face == "TwakeInter-Bold")
  }

  @Test func allFourFacesAreBundledAndRegister() {
    TwakeInter.register()
    for face in TwakeInter.faces {
      #expect(TwakeInter.url(of: face) != nil, "\(face).ttf is missing from the bundle")
      let font = CTFontCreateWithName(face as CFString, 12, nil)
      #expect(CTFontCopyPostScriptName(font) as String == face)
    }
  }
}
