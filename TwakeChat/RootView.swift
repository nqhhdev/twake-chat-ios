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

/// The root coordinator. At launch it restores the saved session, then hands over to the authentication flow, which
/// starts signed in or on TwakeWelcome. Signed in, it shows the chat list, whose Log out goes back to the
/// authentication flow: the root joins the two features, which do not know each other (ADR 0005).
@MainActor @Observable
final class RootCoordinator {
  enum State: Equatable {
    case restoring
    /// The result of the launch restore: the saved session, or `nil` when nobody is signed in or restoring failed.
    case restored(UserSession?)
    /// The saved session could not be restored (for example the homeserver did not answer, or the Keychain or the SDK
    /// store was not available yet). The session and its store are kept, as the Flutter app keeps them when a launch
    /// fails offline; the user tries again. Nothing here deletes a saved session: only Log out does.
    case restoreFailed
  }

  private(set) var state: State = .restoring
  /// Shown on the restore-failed screen when Log out failed and the session is still saved on this device.
  private(set) var logOutErrorMessage: String?

  /// The authentication flow, created once the restore is done.
  private(set) var authentication: AuthenticationCoordinator?

  @ObservationIgnored private let repository: any AuthenticationRepository
  /// Reports a session the server signed out.
  @ObservationIgnored private let sessionExpiry: (any SessionExpiry)?
  @ObservationIgnored private var expiryWatch: Task<Void, Never>?
  /// Shown once on the sign-in form after the server signed this device out.
  var sessionExpiredNotice = false
  @ObservationIgnored private let roomList: (any RoomListRepository)?
  /// The chats the user left.
  @ObservationIgnored private let archive: (any ArchivedRoomsRepository)?
  /// The homeserver's public groups.
  @ObservationIgnored private let publicRooms: (any PublicRoomsRepository)?
  /// What spaces hold.
  @ObservationIgnored private let spaces: (any SpacesRepository)?
  /// Link previews from the homeserver.
  @ObservationIgnored private let linkPreviews: (any LinkPreviewRepository)?
  /// A room's timeline, or with a kind, only that kind of message, for a chat details tab.
  @ObservationIgnored private let makeTimeline: (String, RoomContentKind?) -> any TimelineRepository
  /// One thread's timeline: room id, then the thread's root event id.
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
  @ObservationIgnored private let addressBook: (any AddressBook)?
  /// Meet calls of the account (#92).
  @ObservationIgnored let meetCalls: (any MeetCallRepository)?
  /// Push notifications of the signed-in account.
  @ObservationIgnored let push: PushCenter
  /// Pauses sync in the background and resumes it on return.
  @ObservationIgnored let lifecycle: AppLifecycle
  /// Opens Matrix links in the app; the shell shows what it finds.
  @ObservationIgnored private(set) var links: LinkRouter!
  /// What other apps share into the app, waiting for a chat.
  @ObservationIgnored let shares = ShareCenter()
  @ObservationIgnored let shareSuggestions = ShareSuggestions()
  @ObservationIgnored private let verificationRepository: (any VerificationRepository)?
  /// Unlocks this device with the recovery key kept on ToM (ADR 0024); `nil` (tests) never runs.
  @ObservationIgnored private let deviceUnlock: DeviceUnlocker?
  /// The sign-in the unlock last ran for, so it runs once per sign-in and launch.
  @ObservationIgnored private weak var unlockedSignIn: SignedInViewModel?
  /// A recovery key the unlock made but ToM did not keep: shown once, or it is lost with this device.
  var unsavedRecoveryKey: String?
  @ObservationIgnored private let devicesRepository: (any DevicesRepository)?
  /// Which room events chats show, kept on this device.
  @ObservationIgnored private let chatDisplay: (any ChatDisplaySettingsStore)?
  /// Face ID, Touch ID or the passcode before the app shows anything; `nil` (tests) never locks.
  @ObservationIgnored let appLock: AppLock?
  @ObservationIgnored private let signInConfiguration: SignInConfiguration
  @ObservationIgnored private let webAuthenticator: any WebAuthenticator

  /// - Parameters:
  ///   - roomList: The signed-in user's rooms; the app passes MatrixData's `RoomListProxy`. Tests that never reach the
  ///     chat list leave it out, and the signed-in screen is then empty.
  ///   - signInConfiguration: The build's sign-in URLs.
  ///   - webAuthenticator: Opens the SSO pages.
  init(
    repository: any AuthenticationRepository, roomList: (any RoomListRepository)? = nil,
    archive: (any ArchivedRoomsRepository)? = nil,
    publicRooms: (any PublicRoomsRepository)? = nil,
    spaces: (any SpacesRepository)? = nil,
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
    verification: (any VerificationRepository)? = nil, devices: (any DevicesRepository)? = nil,
    chatDisplay: (any ChatDisplaySettingsStore)? = nil, appLock: AppLock? = nil,
    sync: (any SyncLifecycle)? = nil, sessionExpiry: (any SessionExpiry)? = nil,
    meetCalls: (any MeetCallRepository)? = nil,
    identity: (any IdentityRepository)? = nil, addressBook: (any AddressBook)? = nil,
    signInConfiguration: SignInConfiguration, webAuthenticator: any WebAuthenticator
  ) {
    self.identity = identity
    self.addressBook = addressBook
    let pushCenter = PushCenter(repository: push)
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
    self.deviceUnlock = deviceUnlock
    self.people = people
    self.signInConfiguration = signInConfiguration
    self.webAuthenticator = webAuthenticator
    self.links = LinkRouter(rooms: roomLinks, openDirectChat: openDirectChat())
  }

  /// The chat list of the current signed-in state, kept so the screen keeps its state while it is shown.
  @ObservationIgnored private var chatList:
    (signedIn: SignedInViewModel, viewModel: ChatListViewModel)?

  /// The chat list for a signed-in state, created once per sign-in. Its Log out runs the signed-in state's logout,
  /// which shows the sign-in form when it succeeds.
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

  /// A room's screen model on its own timeline; the shell keeps the open one and closes it through `onLeft`.
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
      threadPrefs: threadPrefs, scrollMemory: scrollMemory)
    shareSuggestions.follow(room)
    return room
  }

  /// Where each chat was left, for this run of the app (issue #138).
  @ObservationIgnored private let scrollMemory = TimelineScrollMemory()

  /// The account's do not disturb, for the chat list's banner.
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

  /// The account's block list, for the "You blocked this person" bar of a direct chat.
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

  /// Which room events a chat shows: the Settings tab's choice, so a change there redraws the open chat.
  private func displaySettings() -> @MainActor () -> ChatDisplaySettings {
    { [weak self] in
      self?.settings?.viewModel.chatDisplay ?? self?.chatDisplay?.load() ?? ChatDisplaySettings()
    }
  }

  /// Whether this session can read encrypted messages, for the chat's banner: its verification, then its recovery.
  private func sessionCheck() -> (@Sendable () async -> SessionWarning?)? {
    guard let verificationRepository, let accountSettings else { return nil }
    return {
      SessionWarning.of(
        verification: await verificationRepository.state(),
        recovery: await accountSettings.recoveryStatus())
    }
  }

  /// True while the unlock with ToM's recovery key runs.
  @ObservationIgnored private var isUnlockingDevice = false

  /// The session check for the prompt after sign-in. It waits for the ToM unlock to end first: a device that is
  /// being unlocked needs nothing from the user, and asking then would show a prompt the unlock is about to make
  /// wrong. The prompt is what is left for a server without ToM, or a key that did not work.
  func sessionCheckAfterUnlock() -> (@Sendable () async -> SessionWarning?)? {
    guard let check = sessionCheck() else { return nil }
    return { [weak self] in
      while await self?.isUnlockingDevice == true {
        try? await Task.sleep(for: .milliseconds(250))
        if Task.isCancelled { return nil }
      }
      return await check()
    }
  }

  /// Unlocks this device with the recovery key kept on ToM, once per sign-in and launch (ADR 0024). Without a key
  /// that works, the room banner and Settings stay the way to verify; a key ToM did not keep is shown to the user.
  func unlockDevice(for signedIn: SignedInViewModel) async {
    guard let deviceUnlock, unlockedSignIn !== signedIn else { return }
    unlockedSignIn = signedIn
    isUnlockingDevice = true
    defer { isUnlockingDevice = false }
    if case .setUpNotSaved(let key) = await deviceUnlock.run() { unsavedRecoveryKey = key }
  }

  /// Rejoins a left chat from its read-only screen (the archive belongs to the room list proxy).
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

  /// Message on a member's profile, or a person found in the chat list search: the shell opens the direct chat when
  /// there is one, as it opens a tapped notification's room, and otherwise a draft chat that creates the chat with
  /// its first message (the app joins the features, ADR 0005).
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

  /// The People search in invite mode, shown from a room's details (the app joins the features, ADR 0005).
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

  /// The Settings tab of a signed-in state, created once per sign-in; its Logout runs the signed-in state's logout.
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
    settings = (signedIn, viewModel)
    return viewModel
  }

  /// A people search for the new chat sheet or the Contacts tab.
  func peopleSearch(
    mode: PeopleSearchViewModel.Mode, onOpen: @escaping @MainActor (String, String) -> Void
  ) -> PeopleSearchViewModel {
    PeopleSearchViewModel(
      mode: mode, repository: people ?? UnavailablePeople(), onOpen: onOpen, identity: identity)
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

  /// Restores the saved session once, also when several windows start it together. A restore error keeps the saved
  /// session and its store and sets `restoreFailed`: calling `start()` again tries once more. The Domain errors cannot
  /// tell a session the server rejected from a fault that passes (the mapper turns both into `unknown`), so the root
  /// never clears the session on its own; Log out (`logOutAfterFailedRestore()`) is the user's way out. While a restore
  /// runs the state is `restoring`, so Log out cannot run beside it.
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

  /// Follows the server signing this device out (from another device, or by an administrator) for as long as the app
  /// runs: each report removes the local session and shows the sign-in form.
  private func watchSessionExpiry() {
    guard expiryWatch == nil, let sessionExpiry else { return }
    expiryWatch = Task { [weak self] in
      for await _ in await sessionExpiry.sessionExpirations() {
        await self?.sessionExpired()
      }
    }
  }

  /// The server no longer knows this device: the saved session and its store are useless. They are removed (the
  /// server call inside `logout` fails, which is expected) and the sign-in form shows with a notice. Nothing happens
  /// when nobody is signed in any more.
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

  /// The way out of `restoreFailed` when the error does not pass: signs out (the repository clears the local session
  /// even when the server cannot be told) and shows the sign-in form. While it runs, `start()` does nothing. When the
  /// repository reports an error the session may still be saved, so the screen stays with an error and the user can
  /// try again, as on the signed-in screen: the user is never shown as signed out while a session is still saved.
  func logOutAfterFailedRestore() async {
    guard state == .restoreFailed, !started else { return }
    started = true
    logOutErrorMessage = nil
    do {
      try await repository.logout()
    } catch {
      logOutErrorMessage = "Could not log out. Please try again."
      started = false
      return
    }
    shareSuggestions.forgetAll()
    state = .restored(nil)
    authentication = makeAuthentication(session: nil)
  }
}

/// The app's root view: it only shows what the root coordinator holds.
struct RootView: View {
  let coordinator: RootCoordinator

  var body: some View {
    content
      .task { await coordinator.start() }
      .alert(
        "You were signed out",
        isPresented: Binding(
          get: { coordinator.sessionExpiredNotice },
          set: { coordinator.sessionExpiredNotice = $0 })
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text("This device was signed out from another device. Sign in again to continue.")
      }
      .overlay {
        if let lock = coordinator.appLock, lock.isLocked || lock.isCovered {
          AppLockScreen(lock: lock).transition(.opacity)
        }
      }
  }

  /// The screens come from the Authentication and ChatList feature packages.
  @ViewBuilder private var content: some View {
    if coordinator.state == .restoreFailed {
      RestoreFailedScreen(
        errorMessage: coordinator.logOutErrorMessage,
        retry: { Task { await coordinator.start() } },
        logOut: { Task { await coordinator.logOutAfterFailedRestore() } })
    } else if let authentication = coordinator.authentication {
      AuthenticationCoordinatorView(coordinator: authentication) { signedIn in
        if let chatList = coordinator.chatList(for: signedIn) {
          ChatShell(
            chatList: chatList, signedIn: signedIn, settings: coordinator.settings(for: signedIn),
            push: coordinator.push, links: coordinator.links, shares: coordinator.shares,
            makePeopleSearch: coordinator.peopleSearch(mode:onOpen:),
            makeRoom: coordinator.room(for:onLeft:),
            checkSession: coordinator.sessionCheckAfterUnlock(),
            meetCalls: coordinator.meetCalls,
            makePhoneContacts: coordinator.phoneContacts
          )
          // Signed in: ask for notifications and register this device.
          .task { await coordinator.push.start() }
          .task { await coordinator.unlockDevice(for: signedIn) }
          .sheet(
            isPresented: Binding(
              get: { coordinator.unsavedRecoveryKey != nil },
              set: { if !$0 { coordinator.unsavedRecoveryKey = nil } })
          ) {
            if let key = coordinator.unsavedRecoveryKey {
              RecoveryKeySheet(key: key) { coordinator.unsavedRecoveryKey = nil }
            }
          }
        }
      }
    } else {
      // Restoring the saved session at launch: the Twake logo, as the Flutter app's splash shows it.
      TwakeLogo(TwakeLogo.welcomeResource)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SysColors.background)
    }
  }
}

/// The timeline of a root built without one (tests that never open a room): it cannot open.
struct UnavailableTimeline: TimelineRepository {
  func open() async throws(TimelineError) -> AsyncStream<[TimelineItem]> { throw .unavailable }
  func loadOlder() async throws(TimelineError) -> Bool { throw .unavailable }
  func send(text: String) async throws(TimelineError) { throw .unavailable }
  func send(emote text: String) async throws(TimelineError) { throw .unavailable }
  func sendAttachment(_ attachment: OutgoingAttachment) async throws(TimelineError) {
    throw .unavailable
  }
  func setTyping(_ isTyping: Bool) async {}
  func createPoll(_ draft: PollDraft) async throws(TimelineError) { throw .unavailable }
  func vote(_ answerIds: [String], in pollEventId: String) async throws(TimelineError) {
    throw .unavailable
  }
  func endPoll(_ pollEventId: String) async throws(TimelineError) { throw .unavailable }
  func setPinned(_ pinned: Bool, eventId: String) async throws(TimelineError) { throw .unavailable }
  func pinnedMessages() async -> [TimelineMessage] { [] }
  func loadDraft() async -> String? { nil }
  func report(eventId: String, reason: String?) async throws(TimelineError) { throw .unavailable }
  func retrySend(transactionId: String) async {}
  func retryDecryption(sessionIds: [String]) async {}
  func discardUnsent(transactionId: String) async throws(TimelineError) { throw .unavailable }
  func ignore(userId: String) async throws(TimelineError) { throw .unavailable }
  func saveDraft(_ text: String) async {}
  func forward(eventId: String, to roomId: String) async throws(TimelineError) {
    throw .unavailable
  }
  func typingMembers() async -> AsyncStream<[String]> { AsyncStream { $0.finish() } }
  func reply(text: String, to eventId: String) async throws(TimelineError) { throw .unavailable }
  func edit(eventId: String, text: String) async throws(TimelineError) { throw .unavailable }
  func redact(eventId: String) async throws(TimelineError) { throw .unavailable }
  func toggleReaction(_ key: String, on eventId: String) async throws(TimelineError) {
    throw .unavailable
  }
  func markAsRead() async {}
  func close() async {}
}

/// The media of a root built without it (tests that never open a room): nothing loads.
struct UnavailableMedia: MediaRepository {
  func thumbnail(_ media: MediaReference, width: Int, height: Int) async throws(MediaError) -> Data
  {
    throw .notSignedIn
  }
  func content(_ media: MediaReference) async throws(MediaError) -> Data { throw .notSignedIn }
  func file(_ media: MediaReference, filename: String) async throws(MediaError) -> URL {
    throw .notSignedIn
  }
}

/// The account settings of a root built without them (tests): nothing is known and nothing changes.
struct UnavailableAccountSettings: AccountSettingsRepository {
  func displayName() async throws(SettingsError) -> String? { nil }
  func setDisplayName(_ name: String) async throws(SettingsError) { throw .notSignedIn }
  func setAvatar(_ picture: PictureUpload) async throws(SettingsError) { throw .notSignedIn }
  func removeAvatar() async throws(SettingsError) { throw .notSignedIn }
  func avatar() async -> MediaReference? { nil }
  func blockedUsers() async throws(SettingsError) -> [BlockedUser] { [] }
  func unblock(userId: String) async throws(SettingsError) { throw .notSignedIn }
  func recoveryStatus() async -> RecoveryStatus { .unknown }
  func recover(recoveryKey: String) async throws(SettingsError) { throw .notSignedIn }
  func enableRecovery() async throws(SettingsError) -> String { throw .notSignedIn }
  func defaultNotificationMode(isDirect: Bool) async -> NotificationMode { .allMessages }
  func setDefaultNotificationMode(_ mode: NotificationMode, isDirect: Bool)
    async throws(SettingsError)
  {
    throw .notSignedIn
  }
}

/// People of a root built without them (tests): nobody is found.
struct UnavailablePeople: PeopleRepository {
  func search(_ text: String) async throws(PeopleError) -> [Person] { throw .notSignedIn }
  func directChat(with userId: String) async throws(PeopleError) -> String { throw .notSignedIn }
  func createGroup(name: String, inviting userIds: [String]) async throws(PeopleError) -> String {
    throw .notSignedIn
  }
}
