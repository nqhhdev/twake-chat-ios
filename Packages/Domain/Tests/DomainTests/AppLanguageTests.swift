import Domain
import Testing

struct AppLanguageTests {
  private let available = ["en", "fr", "Base"]

  @Test func theCommonSettingsLanguageIsUsedWhenTheAppHasIt() {
    #expect(
      AppLanguage.decide(serverLanguage: "fr-FR", available: available, appliedByApp: nil)
        == .use("fr"))
    #expect(
      AppLanguage.decide(serverLanguage: "FR", available: available, appliedByApp: "en")
        == .use("fr"))
  }

  @Test func theSameLanguageIsNotAppliedTwice() {
    #expect(
      AppLanguage.decide(serverLanguage: "fr_FR", available: available, appliedByApp: "fr")
        == .keep)
  }

  @Test func aLanguageTheAppLacksCountsAsNone() {
    #expect(
      AppLanguage.decide(serverLanguage: "vi", available: available, appliedByApp: nil) == .keep)
    #expect(
      AppLanguage.decide(serverLanguage: "base", available: available, appliedByApp: nil) == .keep)
  }

  @Test func withoutALanguageTheDeviceLanguageComesBackOnlyIfTheAppHadChangedIt() {
    #expect(
      AppLanguage.decide(serverLanguage: nil, available: available, appliedByApp: "fr")
        == .followDevice)
    #expect(
      AppLanguage.decide(serverLanguage: nil, available: available, appliedByApp: nil) == .keep)
  }
}
