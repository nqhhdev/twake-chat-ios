import Authentication
import ChatList
import DesignSystem
import Domain
import Foundation
import Observation
import People
import Room
import Settings
import SwiftUI

@MainActor @Observable
final class RootCoordinator {
  enum State: Equatable {
    case restoring
    case restored(UserSession?)
    case restoreFailed
  }

  private(set) var state: State = .restoring
  private(set) var logOutErrorMessage: String?

  private(set) var authentication: AuthenticationCoordinator?

  @ObservationIgnored private let repository: any AuthenticationRepository
  @ObservationIgnored private let sessionExpiry: (any SessionExpiry)?
  @ObservationIgnored private var expiryWatch: Task<Void, Never>?
  var sessionExpiredNotice = false
  @ObservationIgnored private let roomList: (any RoomListRepository)?
  @ObservationIgnored private let archive: (any ArchivedRoomsRepository)?
  @ObservationIgnored private let publicRooms: (any PublicRoomsRepository)?
  @ObservationIgnored private let spaces: (any SpacesRepository)?
  @ObservationIgnored private let folders: (any FoldersRepository)?
  @ObservationIgnored private let linkPreviews: (any LinkPreviewRepository)?
  @ObservationIgnored private let makeTimeline: (String, RoomContentKind?) -> any TimelineRepository
  @ObservationIgnored private let makeThreadTimeline: (String, String) -> any TimelineRepository
  @ObservationIgnored private let media: any MediaRepository
  @ObservationIgnored private let roomDetails: (any RoomDetailsRepository)?
  @ObservationIgnored private let roomSearch: (any RoomSearchRepository)?
  @ObservationIgnored private let savedMessages: (any SavedMessagesRepository)?
  @ObservationIgnored private let threadPrefs: (any ThreadPrefsRepository)?
  @ObservationIgnored private let activityReactions: (any ActivityReactionsRepository)?
  @ObservationIgnored private let accountSettings: (any AccountSettingsRepository)?
  @ObservationIgnored private let people: (any PeopleRepository)?
  @ObservationIgnored private let identity: (any IdentityRepository)?
  @ObservationIgnored let capabilities: (any ServerCapabilitiesRepository)?
  @ObservationIgnored private let accountDeletion: (any AccountDeletionRepository)?
  @ObservationIgnored private let analyticsRepository: (any AnalyticsRepository)?
  @ObservationIgnored private let addressBook: (any AddressBook)?
  @ObservationIgnored private let twakeContactsRepository: (any TwakeContactsRepository)?
  @ObservationIgnored let meetCalls: (any MeetCallRepository)?
  @ObservationIgnored let roomCalls: (any RoomCallRepository)?
  @ObservationIgnored private let gifs: (any GifRepository)?
  @ObservationIgnored private let drive: (any TwakeDriveRepository)?
  @ObservationIgnored let push: PushCenter
  @ObservationIgnored let lifecycle: AppLifecycle
  @ObservationIgnored private(set) var links: LinkRouter!
  @ObservationIgnored let shares: ShareCenter
  @ObservationIgnored let shareSuggestions = ShareSuggestions()
  @ObservationIgnored private let verificationRepository: (any VerificationRepository)?
  @ObservationIgnored private let deviceUnlock: DeviceUnlocker?
  @ObservationIgnored private weak var unlockedSignIn: SignedInViewModel?
  var unsavedRecoveryKey: String?
  @ObservationIgnored private let devicesRepository: (any DevicesRepository)?
  @ObservationIgnored private let chatDisplay: (any ChatDisplaySettingsStore)?
  @ObservationIgnored let appLock: AppLock?
  @ObservationIgnored private let signInConfiguration: SignInConfiguration
  @ObservationIgnored private let webAuthenticator: any WebAuthenticator

  init(
    repository: any AuthenticationRepository, roomList: (any RoomListRepository)? = nil,
    archive: (any ArchivedRoomsRepository)? = nil,
    publicRooms: (any PublicRoomsRepository)? = nil,
    spaces: (any SpacesRepository)? = nil,
    folders: (any FoldersRepository)? = nil,
    linkPreviews: (any LinkPreviewRepository)? = nil,
    makeTimeline: @escaping (String, RoomContentKind?) -> any TimelineRepository = { _, _ in
      UnavailableTimeline()
    },
    makeThreadTimeline: @escaping (String, String) -> any TimelineRepository = { _, _ in
      UnavailableTimeline()
    },
    media: any MediaRepository = UnavailableMedia(),
    roomDetails: (any RoomDetailsRepository)? = nil,
    roomSearch: (any RoomSearchRepository)? = nil,
    savedMessages: (any SavedMessagesRepository)? = nil,
    threadPrefs: (any ThreadPrefsRepository)? = nil,
    activityReactions: (any ActivityReactionsRepository)? = nil,
    roomLinks: (any RoomLinkRepository)? = nil,
    accountSettings: (any AccountSettingsRepository)? = nil,
    deviceUnlock: DeviceUnlocker? = nil,
    people: (any PeopleRepository)? = nil, push: (any PushRepository)? = nil,
    notificationActions: (any NotificationActionRepository)? = nil,
    verification: (any VerificationRepository)? = nil, devices: (any DevicesRepository)? = nil,
    chatDisplay: (any ChatDisplaySettingsStore)? = nil, appLock: AppLock? = nil,
    sync: (any SyncLifecycle)? = nil, sessionExpiry: (any SessionExpiry)? = nil,
    meetCalls: (any MeetCallRepository)? = nil, roomCalls: (any RoomCallRepository)? = nil,
    identity: (any IdentityRepository)? = nil, addressBook: (any AddressBook)? = nil,
    twakeContacts: (any TwakeContactsRepository)? = nil,
    gifs: (any GifRepository)? = nil,
    drive: (any TwakeDriveRepository)? = nil,
    signInConfiguration: SignInConfiguration, webAuthenticator: any WebAuthenticator,
    capabilities: (any ServerCapabilitiesRepository)? = nil,
    accountDeletion: (any AccountDeletionRepository)? = nil,
    analytics: (any AnalyticsRepository)? = nil,
    shares: ShareCenter = ShareCenter()
  ) {
    self.shares = shares
    self.analyticsRepository = analytics
    self.capabilities = capabilities
    self.accountDeletion = accountDeletion
    self.identity = identity
    self.addressBook = addressBook
    self.twakeContactsRepository = twakeContacts
    self.gifs = gifs
    self.drive = drive
    let pushCenter = PushCenter(repository: push, actions: notificationActions)
    self.sessionExpiry = sessionExpiry
    self.push = pushCenter
    self.lifecycle = AppLifecycle(sync: sync, push: pushCenter)
    self.verificationRepository = verification
    self.devicesRepository = devices
    self.chatDisplay = chatDisplay
    self.appLock = appLock
    self.repository = repository
    self.roomList = roomList
    self.archive = archive
    self.publicRooms = publicRooms
    self.spaces = spaces
    self.folders = folders
    self.linkPreviews = linkPreviews
    self.makeTimeline = makeTimeline
    self.makeThreadTimeline = makeThreadTimeline
    self.media = media
    self.roomDetails = roomDetails
    self.roomSearch = roomSearch
    self.savedMessages = savedMessages
    self.threadPrefs = threadPrefs
    self.activityReactions = activityReactions
    self.accountSettings = accountSettings
    self.meetCalls = meetCalls
    self.roomCalls = roomCalls
    self.deviceUnlock = deviceUnlock
    self.people = people
    self.signInConfiguration = signInConfiguration
    self.webAuthenticator = webAuthenticator
    self.links = LinkRouter(rooms: roomLinks, openDirectChat: openDirectChat())
    pushCenter.startSession = { [weak self] in await self?.start() }
  }

  @ObservationIgnored private var chatList:
    (signedIn: SignedInViewModel, viewModel: ChatListViewModel)?

  func chatList(for signedIn: SignedInViewModel) -> ChatListViewModel? {
    if let chatList, chatList.signedIn === signedIn { return chatList.viewModel }
    guard let roomList else { return nil }
    let viewModel = ChatListViewModel(
      repository: roomList, media: media, archive: archive, publicRooms: publicRooms,
      spaces: spaces, messageSearch: roomSearch, doNotDisturb: doNotDisturb(),
      saved: savedMessages, threadPrefs: threadPrefs, activityReactions: activityReactions,
      people: people,
      openPerson: openDirectChat(),
      previewTimeline: { [makeTimeline] roomId in makeTimeline(roomId, nil) },
      presence: presenceLookup(),
      folders: folders,
      logOut: { [weak signedIn, push, shareSuggestions] in
        guard let signedIn else { return false }
        await push.stop()
        shareSuggestions.forgetAll()
        await signedIn.logOut()
        return signedIn.errorMessage == nil
      })
    chatList = (signedIn, viewModel)
    lifecycle.unreadCount = { [weak viewModel] in
      viewModel.map { RoomSummary.appBadge(for: $0.allJoinedRooms) } ?? 0
    }
    return viewModel
  }

  private func presenceLookup() -> (@Sendable (String) async -> Presence?)? {
    guard let roomDetails else { return nil }
    return { userId in await roomDetails.presence(of: userId) }
  }

  func room(for summary: RoomSummary, onLeft: @escaping @MainActor () -> Void) -> RoomViewModel {
    let room = RoomViewModel(
      roomId: summary.id, roomName: summary.name, roomAvatar: summary.avatar,
      repository: makeTimeline(summary.id, nil), media: media,
      details: roomDetails,
      onLeft: { [shareSuggestions] in
        shareSuggestions.forget(summary.id)
        onLeft()
      },
      forwardTargets: { [weak self] in self?.chatList?.viewModel.visibleRooms ?? [] },
      invitePeople: invitePeople(),
      contentTimeline: { [makeTimeline] kind in makeTimeline(summary.id, kind) },
      openDirectChat: openDirectChat(), search: roomSearch,
      isArchived: summary.isArchived, rejoin: rejoin(summary.id), linkPreviews: linkPreviews,
      checkSession: sessionCheck(), display: displaySettings(), blocking: blocking(),
      saved: savedMessages,
      threadTimeline: { [makeThreadTimeline] root in makeThreadTimeline(summary.id, root) },
      threadPrefs: threadPrefs, scrollMemory: scrollMemory, gifs: gifs,
      drive: driveAccess())
    shareSuggestions.follow(room)
    return room
  }

  @ObservationIgnored private let scrollMemory = TimelineScrollMemory()

  private func doNotDisturb() -> ChatListViewModel.DoNotDisturb? {
    guard let accountSettings else { return nil }
    return ChatListViewModel.DoNotDisturb(
      isOn: { await accountSettings.isDoNotDisturbOn() },
      turnOff: {
        do {
          try await accountSettings.setDoNotDisturb(false)
          return true
        } catch {
          return false
        }
      })
  }

  private func driveAccess() -> DriveAccess? {
    guard let drive else { return nil }
    return DriveAccess(repository: drive) { [webAuthenticator] request throws(DriveError) in
      do throws(WebAuthenticationError) {
        return try await webAuthenticator.authenticate(
          url: request.url, callbackScheme: request.callbackScheme)
      } catch {
        throw error == .cancelled ? .cancelled : .signInFailed
      }
    }
  }

  private func blocking() -> RoomViewModel.Blocking? {
    guard let accountSettings else { return nil }
    return RoomViewModel.Blocking(
      isBlocked: { userId in
        ((try? await accountSettings.blockedUsers()) ?? []).contains { $0.id == userId }
      },
      unblock: { userId in
        do {
          try await accountSettings.unblock(userId: userId)
          return true
        } catch {
          return false
        }
      })
  }

  private func displaySettings() -> @MainActor () -> ChatDisplaySettings {
    { [weak self] in
      self?.settings?.viewModel.chatDisplay ?? self?.chatDisplay?.load() ?? ChatDisplaySettings()
    }
  }

  private func sessionCheck() -> (@Sendable () async -> SessionWarning?)? {
    guard let verificationRepository, let accountSettings else { return nil }
    return {
      SessionWarning.of(
        verification: await verificationRepository.state(),
        recovery: await accountSettings.recoveryStatus())
    }
  }

  @ObservationIgnored private var isUnlockingDevice = false

  func sessionCheckAfterUnlock() -> (@Sendable () async -> SessionWarning?)? {
    guard !E2EHarness.skipsSessionPrompt, let check = sessionCheck() else { return nil }
    return { [weak self] in
      while await self?.isUnlockingDevice == true {
        try? await Task.sleep(for: .milliseconds(250))
        if Task.isCancelled { return nil }
      }
      return await check()
    }
  }

  func unlockDevice(for signedIn: SignedInViewModel) async {
    guard let deviceUnlock, unlockedSignIn !== signedIn else { return }
    unlockedSignIn = signedIn
    isUnlockingDevice = true
    defer { isUnlockingDevice = false }
    switch await deviceUnlock.run() {
    case .setUpNotSaved(let key): unsavedRecoveryKey = key
    case .verifiedFromVault:
      NotificationCenter.default.post(name: .encryptionKeysImported, object: nil)
    case .alreadyVerified, .setUp, .needsKey: break
    }
  }

  private func rejoin(_ roomId: String) -> (@MainActor () async -> Bool)? {
    guard let archive else { return nil }
    return {
      do {
        try await archive.rejoin(roomId: roomId)
        return true
      } catch {
        return false
      }
    }
  }

  private func openDirectChat() -> (@MainActor (String) async -> Bool)? {
    guard let people else { return nil }
    return { [push] userId in
      if let roomId = await people.existingDirectChat(with: userId) {
        push.pendingRoomId = roomId
      } else {
        push.pendingDraftUserId = userId
      }
      return true
    }
  }

  private func invitePeople() -> InvitePeople? {
    guard let people, let roomDetails else { return nil }
    return InvitePeople { [identity] roomId, onInvited in
      let search = PeopleSearchViewModel(
        mode: .invite, repository: people, onOpen: { _, _ in },
        invite: { userIds in
          do {
            let failed = try await roomDetails.invite(userIds: userIds, roomId: roomId)
            if failed.count < userIds.count { onInvited() }
            return failed
          } catch {
            return userIds
          }
        },
        identity: identity,
        inviteAddresses: { addresses in
          guard let identity else { return addresses }
          var failed: [ContactAddress] = []
          for address in addresses {
            do {
              try await identity.invite(address, roomId: roomId)
            } catch {
              failed.append(address)
            }
          }
          if failed.count < addresses.count { onInvited() }
          return failed
        })
      return AnyView(InviteScreen(viewModel: search))
    }
  }

  @ObservationIgnored private var settings:
    (signedIn: SignedInViewModel, viewModel: SettingsViewModel)?

  func settings(for signedIn: SignedInViewModel) -> SettingsViewModel {
    if let settings, settings.signedIn === signedIn { return settings.viewModel }
    let viewModel = SettingsViewModel(
      userId: signedIn.userId, repository: accountSettings ?? UnavailableAccountSettings(),
      media: media, verification: verificationRepository.map(VerificationViewModel.init),
      devices: devicesRepository.map(DevicesViewModel.init), chatDisplay: chatDisplay,
      appLock: appLock
    ) { [weak signedIn, push, shareSuggestions] in
      guard let signedIn else { return false }
      await push.stop()
      shareSuggestions.forgetAll()
      await signedIn.logOut()
      return signedIn.errorMessage == nil
    }
    viewModel.personalQR.openLink = { [weak self] url in _ = self?.links.handle(url) }
    if let capabilities {
      viewModel.appGrid = AppGridViewModel(capabilities: capabilities)
      viewModel.help = HelpViewModel(capabilities: capabilities, openDirectChat: openDirectChat())
    }
    if let capabilities, let analyticsRepository {
      viewModel.usageAnalytics = UsageAnalyticsViewModel(
        analytics: Analytics(
          capabilities: capabilities, repository: analyticsRepository,
          appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "0"))
    }
    if let capabilities, let accountDeletion {
      viewModel.deleteAccount = DeleteAccountViewModel(
        userId: signedIn.userId, capabilities: capabilities, repository: accountDeletion,
        signOut: { [weak self] in await self?.accountDeleted() })
    }
    settings = (signedIn, viewModel)
    return viewModel
  }

  func peopleSearch(
    mode: PeopleSearchViewModel.Mode, onOpen: @escaping @MainActor (String, String) -> Void
  ) -> PeopleSearchViewModel {
    PeopleSearchViewModel(
      mode: mode, repository: people ?? UnavailablePeople(), onOpen: onOpen, identity: identity)
  }

  func twakeContacts() -> TwakeContactsViewModel? {
    twakeContactsRepository.map(TwakeContactsViewModel.init)
  }

  func phoneContacts() -> PhoneContactsViewModel? {
    guard let identity, let addressBook else { return nil }
    return PhoneContactsViewModel(addressBook: addressBook, identity: identity)
  }

  @ObservationIgnored private var started = false

  private func makeAuthentication(session: UserSession?) -> AuthenticationCoordinator {
    AuthenticationCoordinator(
      repository: repository, configuration: signInConfiguration,
      webAuthenticator: webAuthenticator,
      session: session)
  }

  func start() async {
    guard !started else { return }
    started = true
    state = .restoring
    logOutErrorMessage = nil
    let session: UserSession?
    do {
      session = try await repository.restoreSession()
    } catch {
      state = .restoreFailed
      started = false
      return
    }
    state = .restored(session)
    authentication = makeAuthentication(session: session)
    watchSessionExpiry()
  }

  private func watchSessionExpiry() {
    guard expiryWatch == nil, let sessionExpiry else { return }
    expiryWatch = Task { [weak self] in
      for await _ in await sessionExpiry.sessionExpirations() {
        await self?.sessionExpired()
      }
    }
  }

  func applyCommonSettingsLanguage() async {
    guard let accountSettings else { return }
    let language = await accountSettings.commonSettingsLanguage()
    if language == nil, await capabilities?.current().tom != nil { return }
    CommonSettingsLanguage().apply(language)
  }

  func accountDeleted() async {
    guard case .restored = state, case .signedIn? = authentication?.screen else { return }
    await push.stop()
    shareSuggestions.forgetAll()
    try? await repository.logout()
    chatList = nil
    state = .restored(nil)
    authentication = makeAuthentication(session: nil)
  }

  func sessionExpired() async {
    guard case .restored = state, case .signedIn? = authentication?.screen else { return }
    await push.stop()
    shareSuggestions.forgetAll()
    try? await repository.logout()
    guard (try? await repository.restoreSession()) == nil else { return }
    chatList = nil
    sessionExpiredNotice = true
    state = .restored(nil)
    authentication = makeAuthentication(session: nil)
  }

  func retire() async {
    await lifecycle.stop()
  }

  func discardSession() async {
    try? await repository.logout()
  }

  func logOutAfterFailedRestore() async {
    guard state == .restoreFailed, !started else { return }
    started = true
    logOutErrorMessage = nil
    do {
      try await repository.logout()
    } catch {
      logOutErrorMessage = String(localized: "Could not log out. Please try again.")
      started = false
      return
    }
    shareSuggestions.forgetAll()
    state = .restored(nil)
    authentication = makeAuthentication(session: nil)
  }
}
