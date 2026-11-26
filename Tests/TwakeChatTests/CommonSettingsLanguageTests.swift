import Foundation
import Testing

@testable import TwakeChat

struct CommonSettingsLanguageTests {
  private let suite = "CommonSettingsLanguageTests.\(UUID().uuidString)"

  private func makeLanguage() -> (CommonSettingsLanguage, UserDefaults) {
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return (CommonSettingsLanguage(defaults: defaults, available: ["en", "fr", "Base"]), defaults)
  }

  private func stored(_ defaults: UserDefaults, _ key: String) -> Any? {
    defaults.persistentDomain(forName: suite)?[key]
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
    #expect(stored(defaults, CommonSettingsLanguage.languagesKey) == nil)
    #expect(stored(defaults, CommonSettingsLanguage.appliedKey) == nil)
  }

  @Test func aLanguageTheUserChoseIsLeftAloneOnAPlainServer() {
    let (language, defaults) = makeLanguage()
    defaults.set(["fr"], forKey: CommonSettingsLanguage.languagesKey)
    language.apply(nil)
    #expect(defaults.stringArray(forKey: CommonSettingsLanguage.languagesKey) == ["fr"])
  }
}
