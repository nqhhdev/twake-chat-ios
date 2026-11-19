import AppShared
import Foundation

/// What the UI tests (`TwakeChatUITests`, test plan `E2E`) set in the launch environment, read in Debug builds only.
/// Release builds ignore it. The tests start the app with:
/// - `IS_RUNNING_E2E_TESTS=1`;
/// - `E2E_RESET_SESSION=1` to delete the saved session and the SDK store before launch;
/// - `E2E_HOMESERVER` to put the test homeserver in the homeserver field instead of the build's default.
/// The pattern is element-x-ios's `IS_RUNNING_INTEGRATION_TESTS` launch environment; see docs/e2e.md.
enum E2EHarness {
  private static var environment: [String: String] { ProcessInfo.processInfo.environment }

  static var isRunning: Bool {
    #if DEBUG
      environment["IS_RUNNING_E2E_TESTS"] == "1"
    #else
      false
    #endif
  }

  /// The test homeserver, or `nil` outside the UI tests.
  static var homeserver: URL? {
    guard isRunning, let value = environment["E2E_HOMESERVER"], !value.isEmpty else { return nil }
    return URL(string: value)
  }

  static func resetIfAsked(storeDirectory: URL, sessionStore: KeychainSessionStore) {
    guard isRunning, environment["E2E_RESET_SESSION"] == "1" else { return }
    try? sessionStore.delete()
    let files = FileManager.default
    for item
      in (try? files.contentsOfDirectory(at: storeDirectory, includingPropertiesForKeys: nil)) ?? []
    {
      try? files.removeItem(at: item)
    }
  }
}
