import Domain
import Foundation

struct CommonSettingsLanguage {
  static let appliedKey = "app.twake.chat.commonSettingsLanguage"
  static let languagesKey = "AppleLanguages"

  let defaults: UserDefaults
  let available: [String]

  init(defaults: UserDefaults = .standard, available: [String] = Bundle.main.localizations) {
    self.defaults = defaults
    self.available = available
  }

  func apply(_ serverLanguage: String?) {
    let applied = defaults.string(forKey: Self.appliedKey)
    switch AppLanguage.decide(
      serverLanguage: serverLanguage, available: available, appliedByApp: applied)
    {
    case .keep:
      break
    case .use(let language):
      defaults.set([language], forKey: Self.languagesKey)
      defaults.set(language, forKey: Self.appliedKey)
    case .followDevice:
      defaults.removeObject(forKey: Self.languagesKey)
      defaults.removeObject(forKey: Self.appliedKey)
    }
  }
}
