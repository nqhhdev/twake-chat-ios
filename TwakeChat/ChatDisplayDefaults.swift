import Domain
import Foundation

/// The chat display settings in this app's `UserDefaults`; a switch never set reads as on, the Flutter default. The
/// keys are the app's own: the Flutter app's (`chat.twake.*`, `chat.fluffy.*`) are not read (ADR 0017).
struct ChatDisplayDefaults: ChatDisplaySettingsStore {
  static let unimportantKey = "app.twake.ios.chat.display.hidesUnimportantEvents"
  static let unknownKey = "app.twake.ios.chat.display.hidesUnknownEvents"

  /// `nil` is the app's standard defaults; tests pass a suite of their own.
  let suiteName: String?

  init(suiteName: String? = nil) {
    self.suiteName = suiteName
  }

  private var defaults: UserDefaults {
    suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
  }

  func load() -> ChatDisplaySettings {
    let defaults = defaults
    return ChatDisplaySettings(
      hidesUnimportantEvents: defaults.object(forKey: Self.unimportantKey) as? Bool ?? true,
      hidesUnknownEvents: defaults.object(forKey: Self.unknownKey) as? Bool ?? true)
  }

  func save(_ settings: ChatDisplaySettings) {
    let defaults = defaults
    defaults.set(settings.hidesUnimportantEvents, forKey: Self.unimportantKey)
    defaults.set(settings.hidesUnknownEvents, forKey: Self.unknownKey)
  }
}
