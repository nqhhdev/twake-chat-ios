import Foundation
import Testing

@testable import TwakeChat

struct CommonSettingsLanguageTests {
  private func makeLanguage() -> (CommonSettingsLanguage, UserDefaults) {
    let name = "CommonSettingsLanguageTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return (CommonSettingsLanguage(defaults: defaults, available: ["en", "fr", "Base"]), defaults)
  }

  @Test func theServerLanguageBecomesTheAppLanguage() {
    let (language, defaults) = makeLanguage()
    language.apply("fr-FR")
    #expect(defaults.stringArray(forKey: CommonSettingsLanguage.languagesKey) == ["fr"])
    #expect(defaults.string(forKey: CommonSettingsLanguage.appliedKey) == "fr")
  }

  @Test func withoutAServerLanguageTheDeviceLanguageComesBack() {
    let (language, defaults) = makeLanguage()
    language.apply("fr")
    language.apply(nil)
    #expect(defaults.object(forKey: CommonSettingsLanguage.languagesKey) == nil)
    #expect(defaults.string(forKey: CommonSettingsLanguage.appliedKey) == nil)
  }

  @Test func aLanguageTheUserChoseIsLeftAloneOnAPlainServer() {
    let (language, defaults) = makeLanguage()
    defaults.set(["fr"], forKey: CommonSettingsLanguage.languagesKey)
    language.apply(nil)
    #expect(defaults.stringArray(forKey: CommonSettingsLanguage.languagesKey) == ["fr"])
  }
}
