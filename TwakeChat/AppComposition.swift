import AppShared
import Authentication
import Domain
import Foundation
import MatrixData
import People
import UIKit

struct AppComposition {
  let registry: AccountRegistry
  let accessGroup: String
  let appLock: AppLock

  func sessionStore(_ slot: AccountSlot) -> KeychainSessionStore {
    KeychainSessionStore(
      service: "app.twake.ios.chat", accessGroup: accessGroup, account: slot.keychainAccount)
  }

  @MainActor
  func root(
    for slot: AccountSlot, onSessionChange: @escaping @Sendable (SessionChange) -> Void
  ) -> RootCoordinator {
    let repository = MatrixAuthenticationRepository(
      storeDirectory: registry.storeDirectory(for: slot), sessionStore: sessionStore(slot),
      signsOutWithoutStore: true, onSessionChange: onSessionChange)
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
    let capabilities = ServerCapabilitiesProxy(
      authentication: repository, build: BuildServices.from(.main))
    let devices = DevicesProxy(authentication: repository)
    let recoveryVault = TomRecoveryVault(authentication: repository, capabilities: capabilities)
    let accountSettings = AccountSettingsProxy(
      authentication: repository, recoveryVault: recoveryVault, capabilities: capabilities)
    return RootCoordinator(
      repository: repository, roomList: roomList, archive: roomList,
      publicRooms: PublicRoomsProxy(authentication: repository),
      spaces: SpacesProxy(authentication: repository),
      folders: FoldersProxy(authentication: repository),
      linkPreviews: LinkPreviewProxy(authentication: repository),
      makeTimeline: { TimelineProxy(roomId: $0, authentication: repository, only: $1) },
      makeThreadTimeline: {
        TimelineProxy(roomId: $0, authentication: repository, threadRoot: $1)
      },
      media: MediaProxy(authentication: repository),
      roomDetails: RoomDetailsProxy(authentication: repository),
      roomSearch: RoomSearchProxy(authentication: repository),
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
      appLock: appLock, sync: repository, sessionExpiry: repository,
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
      analytics: AnalyticsProxy(authentication: repository))
  }
}
