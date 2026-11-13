import Domain
import Foundation
import Testing

@testable import TwakeChat

@Suite struct ChatDisplayDefaultsTests {
  private let suite = "ChatDisplayDefaultsTests-\(UUID().uuidString)"

  @Test func switchesNeverSetReadAsOn() {
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    #expect(ChatDisplayDefaults(suiteName: suite).load() == ChatDisplaySettings())
  }

  @Test func savedSwitchesComeBack() {
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    let saved = ChatDisplaySettings(hidesUnimportantEvents: false, hidesUnknownEvents: true)
    ChatDisplayDefaults(suiteName: suite).save(saved)
    #expect(ChatDisplayDefaults(suiteName: suite).load() == saved)
  }
}
