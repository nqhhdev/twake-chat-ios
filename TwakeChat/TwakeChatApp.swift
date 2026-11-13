import AppShared
import Authentication
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
    // The build configuration sets the sign-in URLs: staging in Debug, Twake SaaS in Release. None is a secret.
    func url(_ key: String) -> URL? {
      (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap {
        $0.isEmpty ? nil : URL(string: $0)
      }
    }
    let configuration = SignInConfiguration(
      registrationURL: url("RegistrationURL"), workplaceHomeserver: url("WorkplaceHomeserver"),
      defaultHomeserver: url("DefaultHomeserver"),
      privacyURL: url("PrivacyURL") ?? URL(string: "https://twake.app/policy")!)
    _root = State(
      initialValue: RootCoordinator(
        repository: repository, roomList: RoomListProxy(authentication: repository),
        makeTimeline: { TimelineProxy(roomId: $0, authentication: repository) },
        media: MediaProxy(authentication: repository),
        roomDetails: RoomDetailsProxy(authentication: repository),
        signInConfiguration: configuration, webAuthenticator: SystemWebAuthenticator()))
  }

  var body: some Scene {
    WindowGroup {
      RootView(coordinator: root)
    }
  }
}
