import AppShared
import Authentication
import Domain
import Foundation
import MatrixData
import People
import SwiftUI

@main
struct TwakeChatApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var root: RootCoordinator
  @Environment(\.scenePhase) private var scenePhase

  /// The composition root (ADR 0004): builds the session store and the repositories, and passes them down.
  init() {
    MatrixPlatform.setUp()
    guard let registry = AccountRegistry.inAppGroup(),
      let accessGroup = Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String
    else {
      preconditionFailure("The app's entitlements give it no App Group or Keychain access group.")
    }
    func sessionStore(_ slot: AccountSlot) -> KeychainSessionStore {
      KeychainSessionStore(
        service: "app.twake.ios.chat", accessGroup: accessGroup, account: slot.keychainAccount)
    }
    #if DEBUG
      E2EHarness.resetIfAsked(
        storeDirectory: registry.storeDirectory(for: .legacy), sessionStore: sessionStore(.legacy),
        registry: registry)
    #endif
    let accounts = registry.migrate(legacyUserId: try? sessionStore(.legacy).load()?.userId)
    let slot = accounts.active?.slot ?? accounts.slotForSignIn()
    let repository = MatrixAuthenticationRepository(
      storeDirectory: registry.storeDirectory(for: slot), sessionStore: sessionStore(slot),
      signsOutWithoutStore: true,
      onSessionChange: { change in
        switch change {
        case .signedIn(let userId): registry.update { _ = $0.add(userId: userId, slot: slot) }
        case .signedOut: registry.update { _ = $0.remove(slot: slot) }
        }
      })
    // The build configuration sets the sign-in URLs: staging in Debug, Twake SaaS in Release. None is a secret.
    func url(_ key: String) -> URL? {
      (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap {
        $0.isEmpty ? nil : URL(string: $0)
      }
    }
    let configuration = SignInConfiguration(
      registrationURL: url("RegistrationURL"), workplaceHomeserver: url("WorkplaceHomeserver"),
      defaultHomeserver: E2EHarness.homeserver ?? url("DefaultHomeserver"),
      privacyURL: url("PrivacyURL") ?? URL(string: "https://twake.app/policy")!)
    let roomList = RoomListProxy(authentication: repository)
    let messageIndex = MessageIndex(authentication: repository)
    let capabilities = ServerCapabilitiesProxy(
      authentication: repository, build: BuildServices.from(.main))
    let devices = DevicesProxy(authentication: repository)
    let recoveryVault = TomRecoveryVault(authentication: repository, capabilities: capabilities)
    let accountSettings = AccountSettingsProxy(
      authentication: repository, recoveryVault: recoveryVault, capabilities: capabilities)
    _root = State(
      initialValue: RootCoordinator(
        repository: repository, roomList: roomList, archive: roomList,
        publicRooms: PublicRoomsProxy(authentication: repository),
        spaces: SpacesProxy(authentication: repository),
        folders: FoldersProxy(authentication: repository),
        linkPreviews: LinkPreviewProxy(authentication: repository),
        makeTimeline: {
          TimelineProxy(
            roomId: $0, authentication: repository, only: $1, index: messageIndex,
            capabilities: capabilities)
        },
        makeThreadTimeline: {
          TimelineProxy(
            roomId: $0, authentication: repository, threadRoot: $1, index: messageIndex,
            capabilities: capabilities)
        },
        media: MediaProxy(authentication: repository),
        roomDetails: RoomDetailsProxy(authentication: repository),
        roomSearch: RoomSearchProxy(authentication: repository, index: messageIndex),
        savedMessages: SavedMessagesProxy(authentication: repository),
        threadPrefs: ThreadPrefsProxy(authentication: repository),
        activityReactions: ActivityReactionsProxy(authentication: repository),
        roomLinks: RoomLinkProxy(authentication: repository),
        accountSettings: accountSettings,
        deviceUnlock: DeviceUnlocker(encryption: accountSettings, vault: recoveryVault),
        people: PeopleProxy(authentication: repository, capabilities: capabilities),
        push: url("PushGatewayURL").map {
          PusherProxy(
            authentication: repository, gatewayURL: $0.absoluteString,
            deviceName: "Twake Chat on \(UIDevice.current.model)")
        },
        notificationActions: NotificationActionProxy(authentication: repository),
        verification: VerificationProxy(authentication: repository),
        devices: devices, chatDisplay: ChatDisplayDefaults(),
        appLock: AppLock(), sync: repository, sessionExpiry: repository,
        meetCalls: MeetCallProxy(authentication: repository, capabilities: capabilities),
        roomCalls: ElementCallProxy(
          authentication: repository, fallbackURL: url("ElementCallURL"),
          clientId: Bundle.main.bundleIdentifier ?? "app.twake.ios.chat"),
        identity: IdentityServerProxy(authentication: repository, capabilities: capabilities),
        addressBook: SystemAddressBook(),
        twakeContacts: TomContactsProxy(authentication: repository, capabilities: capabilities),
        gifs: url("TwakeProxyURL").map { GifProxy(baseURL: $0, authentication: repository) },
        signInConfiguration: configuration, webAuthenticator: SystemWebAuthenticator(),
        capabilities: capabilities, accountDeletion: devices,
        analytics: AnalyticsProxy(authentication: repository)))
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
