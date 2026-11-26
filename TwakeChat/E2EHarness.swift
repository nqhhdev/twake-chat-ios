import AppShared
import Foundation

enum E2EHarness {
  private static var environment: [String: String] { ProcessInfo.processInfo.environment }

  static var isRunning: Bool {
    #if DEBUG
      environment["IS_RUNNING_E2E_TESTS"] == "1"
    #else
      false
    #endif
  }

  static var skipsSessionPrompt: Bool {
    isRunning && environment["E2E_SKIP_SESSION_PROMPT"] == "1"
  }

  static var homeserver: URL? {
    guard isRunning, let value = environment["E2E_HOMESERVER"], !value.isEmpty else { return nil }
    return URL(string: value)
  }

  static func resetIfAsked(
    storeDirectory: URL, sessionStore: KeychainSessionStore, registry: AccountRegistry
  ) {
    guard isRunning, environment["E2E_RESET_SESSION"] == "1" else { return }
    try? sessionStore.delete()
    try? FileManager.default.removeItem(at: registry.fileURL)
    let files = FileManager.default
    for item
      in (try? files.contentsOfDirectory(at: storeDirectory, includingPropertiesForKeys: nil)) ?? []
    {
      try? files.removeItem(at: item)
    }
  }
}
