import AppShared
import Foundation
import MatrixData
import SwiftUI

@main
struct TwakeChatApp: App {
  @State private var root: RootCoordinator

  /// The composition root (ADR 0004): builds the session store and the repositories, and passes them down.
  init() {
    MatrixPlatform.setUp()
    guard let storeDirectory = AppGroupContainer().sdkStoreDirectory(),
      let accessGroup = Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String
    else {
      preconditionFailure("The app's entitlements give it no App Group or Keychain access group.")
    }
    let repository = MatrixAuthenticationRepository(
      storeDirectory: storeDirectory,
      sessionStore: KeychainSessionStore(service: "app.twake.ios.chat", accessGroup: accessGroup))
    #if DEBUG
      // The Debug build configuration sets the development homeserver (ADR 0019); it is not a secret.
      let defaultHomeserver =
        (Bundle.main.object(forInfoDictionaryKey: "DefaultHomeserver") as? String)
        .flatMap(URL.init(string:))
    #else
      let defaultHomeserver: URL? = nil
    #endif
    _root = State(
      initialValue: RootCoordinator(
        repository: repository, roomList: RoomListProxy(authentication: repository),
        defaultHomeserver: defaultHomeserver))
  }

  var body: some Scene {
    WindowGroup {
      RootView(coordinator: root)
    }
  }
}
