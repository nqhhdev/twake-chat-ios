import AppShared
import Authentication
import Foundation
import MatrixData
import SwiftUI

@main
struct TwakeChatApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var root: RootCoordinator
  @Environment(\.scenePhase) private var scenePhase

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
    let roomList = RoomListProxy(authentication: repository)
    _root = State(
      initialValue: RootCoordinator(
        repository: repository, roomList: roomList, archive: roomList,
        publicRooms: PublicRoomsProxy(authentication: repository),
        spaces: SpacesProxy(authentication: repository),
        linkPreviews: LinkPreviewProxy(authentication: repository),
        makeTimeline: { TimelineProxy(roomId: $0, authentication: repository, only: $1) },
        makeThreadTimeline: {
          TimelineProxy(roomId: $0, authentication: repository, threadRoot: $1)
        },
        media: MediaProxy(authentication: repository),
        roomDetails: RoomDetailsProxy(authentication: repository),
        roomSearch: RoomSearchProxy(authentication: repository),
        savedMessages: SavedMessagesProxy(authentication: repository),
        roomLinks: RoomLinkProxy(authentication: repository),
        accountSettings: AccountSettingsProxy(authentication: repository),
        people: PeopleProxy(authentication: repository),
        push: url("PushGatewayURL").map {
          PusherProxy(
            authentication: repository, gatewayURL: $0.absoluteString,
            deviceName: "Twake Chat on \(UIDevice.current.model)")
        },
        verification: VerificationProxy(authentication: repository),
        devices: DevicesProxy(authentication: repository), chatDisplay: ChatDisplayDefaults(),
        appLock: AppLock(), sync: repository,
        signInConfiguration: configuration, webAuthenticator: SystemWebAuthenticator()))
    AppDelegate.push = root.push
  }

  var body: some Scene {
    WindowGroup {
      RootView(coordinator: root)
        .onChange(of: scenePhase) { _, phase in root.lifecycle.phaseChanged(to: phase) }
        // The lock asks at launch too, so this one also runs for the first phase.
        .onChange(of: scenePhase, initial: true) { _, phase in
          root.appLock?.phaseChanged(to: phase)
        }
        // `twake.chat://chat/…` and `matrix:` links from other apps (Safari's "Open in Twake Chat").
        .onOpenURL { url in
          if url == SharedInbox.openURL { root.shares.load() } else { root.links.handle(url) }
        }
    }
  }
}
