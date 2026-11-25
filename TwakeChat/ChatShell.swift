import Authentication
import ChatList
import DesignSystem
import Domain
import People
import Room
import Settings
import SwiftUI

/// The signed-in screens, laid out as twake-on-matrix `AppAdaptiveScaffold` (ADR 0022) inside Apple's system tab view
/// (owner decision 2026-11-13): Contacts, Chats and Settings are SwiftUI `Tab`s in a `.sidebarAdaptable` `TabView`, so
/// iOS draws its own tab bar (or sidebar where the system offers one) on every screen, folded or unfolded. On a phone
/// held upright and on a folded Duo a chat is pushed over the list and hides the tab bar, as Messages does; from 905 pt
/// the chat list is a 472 pt column beside the open chat. Folding, unfolding or rotating keeps the tab and the chat. The
/// shell joins the features, which do not know each other (ADR 0005).
struct ChatShell: View {
  enum Destination: Hashable {
    case contacts, chats, settings
  }

  let chatList: ChatListViewModel
  let signedIn: SignedInViewModel
  let settings: SettingsViewModel
  /// Opens the room of a tapped notification.
  let push: PushCenter
  /// Matrix links tapped in the app or handed to it.
  @Bindable var links: LinkRouter
  /// Items other apps shared, waiting for a chat.
  let shares: ShareCenter
  /// Makes a people search; the closure it is given opens the chat it found or created.
  let makePeopleSearch:
    (PeopleSearchViewModel.Mode, @escaping @MainActor (String, String) -> Void) ->
      PeopleSearchViewModel
  /// Makes a room's screen model; the closure it is given closes the room (after the user left it).
  let makeRoom: (RoomSummary, @escaping @MainActor () -> Void) -> RoomViewModel
  /// Whether this session can read encrypted messages; asked once after sign-in, to offer the way to fix it.
  var checkSession: (@Sendable () async -> SessionWarning?)?

  /// How the shell lays out a screen of `width` points (safe areas included, as Flutter measures).
  struct Layout: Equatable {
    /// The chat list beside the chat (ADR 0022).
    let isTwoColumn: Bool

    init(width: CGFloat) {
      isTwoColumn = TwakeLayout.isTwoColumn(width: width)
    }
  }

  @State private var destination = Destination.chats
  @State private var room: RoomViewModel?
  @State private var isRoomPushed = false
  @State private var newChat: PeopleSearchViewModel?
  /// The draft chat with someone picked on a member's profile or in the chat list search.
  @State private var draftChat: PeopleSearchViewModel?
  @State private var contacts: PeopleSearchViewModel?
  @State private var settingsPage: SettingsPage? = .security
  /// Privacy & Security over the chat, from the banner that warns encrypted messages may not show.
  @State private var isFixingSession = false
  /// What the prompt after sign-in asks the user to do, as the Flutter app asks for recovery right after login.
  @State private var sessionPrompt: SessionWarning?
  @State private var quickSwitcher: QuickSwitcherViewModel?

  var body: some View {
    GeometryReader { geometry in
      // Flutter's breakpoints compare the whole screen width (MediaQuery), safe areas included.
      let layout = Layout(
        width: geometry.size.width + geometry.safeAreaInsets.leading
          + geometry.safeAreaInsets.trailing)
      TabView(selection: $destination) {
        Tab("Contacts", systemImage: "person.2", value: Destination.contacts) {
          NavigationStack { contactsContent }
        }
        Tab("Chats", systemImage: "message", value: Destination.chats) {
          chatsContent(isTwoColumn: layout.isTwoColumn)
        }
        Tab("Settings", systemImage: "gearshape", value: Destination.settings) {
          settingsContent(isTwoColumn: layout.isTwoColumn)
        }
      }
      .tabViewStyle(.sidebarAdaptable)
      // A request from another of the user's devices opens the verification sheet wherever the user is.
      .task { await settings.verification?.follow() }
      .sheet(
        isPresented: Binding(
          get: { settings.verification?.isPresentingRequest == true },
          set: { if !$0 { Task { await settings.verification?.dismiss() } } })
      ) {
        if let verification = settings.verification {
          VerificationSheet(viewModel: verification)
        }
      }
      .onChange(of: push.pendingRoomId, initial: true) { _, roomId in
        guard let roomId else { return }
        let fallbackName = push.pendingRoomName ?? "…"
        push.pendingRoomId = nil
        push.pendingRoomName = nil
        destination = .chats
        Task { await openWhenKnown(roomId, name: fallbackName) }
      }
      .onChange(of: push.pendingDraftUserId, initial: true) { _, userId in
        guard let userId else { return }
        push.pendingDraftUserId = nil
        let search = makePeopleSearch(.direct) { roomId, name in
          draftChat = nil
          open(
            RoomSummary(
              id: roomId, name: name, lastMessageText: nil, lastMessageSender: nil,
              lastActivity: nil))
        }
        search.draft(with: Person(id: userId, displayName: nil))
        // A member's profile is a sheet that closes as this arrives; a sheet shown while another closes is
        // dropped.
        Task {
          try? await Task.sleep(for: .milliseconds(500))
          draftChat = search
        }
      }
      .sheet(item: $draftChat) { search in
        if let person = search.draftChat {
          DraftChatScreen(person: person, viewModel: search)
        }
      }
      .onChange(of: links.opening) { _, opening in
        guard let opening else { return }
        links.opening = nil
        destination = .chats
        Task { await openWhenKnown(opening.roomId, name: "…", at: opening.eventId) }
      }
      .sheet(item: $links.joining) { joining in JoinRoomSheet(joining: joining, router: links) }
      .quickSwitcher($quickSwitcher) {
        QuickSwitcherViewModel(list: chatList) { summary in
          quickSwitcher = nil
          destination = .chats
          open(summary)
        }
      }
      .task { await promptForSessionFix() }
      .alert(
        "Unlock your encrypted messages",
        isPresented: Binding(
          get: { sessionPrompt != nil }, set: { if !$0 { sessionPrompt = nil } }),
        presenting: sessionPrompt
      ) { warning in
        Button(warning == .unverified ? "Verify this device" : "Enter recovery key") {
          isFixingSession = true
        }
        Button("Later", role: .cancel) {}
      } message: { warning in
        Text(
          warning == .unverified
            ? "Verify this device with another one, or with your recovery key, to read your encrypted messages."
            : "Enter your recovery key to read the encrypted messages sent before you signed in here."
        )
      }
      .sheet(
        isPresented: $isFixingSession,
        onDismiss: { Task { await room?.refreshSessionWarning() } }
      ) {
        NavigationStack {
          SettingsPageView(page: .security, viewModel: settings)
            .task { await settings.load() }
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button("Done") { isFixingSession = false }
              }
            }
        }
      }
      .sheet(
        isPresented: Binding(
          get: { shares.pending != nil },
          set: { if !$0, shares.pending != nil { shares.cancel() } }
        )
      ) {
        if let items = shares.pending {
          ShareTargetSheet(
            items: items, rooms: Self.shareTargets(chatList.state),
            onPick: { summary in
              guard let share = shares.take() else { return }
              destination = .chats
              open(summary)
              room?.receive(share)
            },
            onCancel: { shares.cancel() })
        }
      }
      .confirmationDialog(
        "Chat with \(links.person ?? "")?",
        isPresented: Binding(get: { links.person != nil }, set: { if !$0 { links.person = nil } }),
        titleVisibility: .visible
      ) {
        if let person = links.person {
          Button("Message") { Task { await links.message(person) } }
          Button("Copy ID") { UIPasteboard.general.string = person }
        }
      }
      .alert(
        links.errorMessage ?? "",
        isPresented: Binding(
          get: { links.errorMessage != nil && links.joining == nil },
          set: { if !$0 { links.clearError() } })
      ) {
        Button("OK", role: .cancel) {}
      }
      // A matrix.to link in a message opens here; any other link goes to the system (Safari).
      .environment(
        \.openURL, OpenURLAction { url in links.handle(url) ? .handled : .systemAction }
      )
      .twakeTabBarMinimizesOnScroll()
      .tint(SysColors.primary)
    }
  }

  /// Settings: on a phone a pushed page; from 905 pt the list with the chosen page beside it, as iPad Settings.
  @ViewBuilder private func settingsContent(isTwoColumn: Bool) -> some View {
    if isTwoColumn {
      HStack(spacing: 0) {
        NavigationStack { SettingsScreen(viewModel: settings, selection: $settingsPage) }
          .ignoresSafeArea(.container, edges: .trailing)
          .frame(width: TwakeLayout.listColumnWidth)
        Rectangle().fill(SysColors.surface).frame(width: 1)
        NavigationStack {
          SettingsPageView(page: settingsPage ?? .security, viewModel: settings)
            .id(settingsPage)
        }
      }
      .background(SysColors.background)
    } else {
      NavigationStack { SettingsScreen(viewModel: settings) }
    }
  }

  /// The Contacts tab keeps its search while the app runs; a contact opens their chat in the Chats tab.
  private var contactsContent: some View {
    Group {
      if let contacts { ContactsScreen(viewModel: contacts) } else { Color.clear }
    }
    .task {
      guard contacts == nil else { return }
      contacts = makePeopleSearch(.direct) { roomId, name in
        destination = .chats
        open(
          RoomSummary(
            id: roomId, name: name, lastMessageText: nil, lastMessageSender: nil, lastActivity: nil)
        )
      }
    }
  }

  /// The chat list, with the open chat beside it from 905 pt, or pushed over it below. Beside the chat the open room is
  /// highlighted in the list; on a phone the chat covers the list, so nothing is.
  @ViewBuilder private func chatsContent(isTwoColumn: Bool) -> some View {
    if isTwoColumn {
      HStack(spacing: 0) {
        NavigationStack { chatListScreen(isBesideChat: true) }
          .frame(width: TwakeLayout.listColumnWidth)
        Rectangle().fill(SysColors.surface).frame(width: 1)
        NavigationStack {
          if let room {
            RoomScreen(viewModel: room).id(room.roomId)
              .onAppear { push.openRoomId = room.roomId }
              .onDisappear { if push.openRoomId == room.roomId { push.openRoomId = nil } }
          } else {
            TwakeLogo(TwakeLogo.welcomeResource)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .background(SysColors.background)
          }
        }
        // Another chat starts its own stack: the details or search pushed over the last one must not stay.
        .id(room?.roomId)
      }
      .background(SysColors.background)
    } else {
      NavigationStack {
        chatListScreen(isBesideChat: false)
          .navigationDestination(isPresented: $isRoomPushed) {
            if let room {
              // The composer takes the bottom of the screen, so the tab bar steps aside, as in Messages.
              RoomScreen(viewModel: room).id(room.roomId)
                .onAppear { push.openRoomId = room.roomId }
                .onDisappear { if push.openRoomId == room.roomId { push.openRoomId = nil } }
                .toolbar(.hidden, for: .tabBar)
            }
          }
      }
    }
  }

  private func chatListScreen(isBesideChat: Bool) -> some View {
    ChatListScreen(
      viewModel: chatList, selectedRoomId: isBesideChat ? room?.roomId : nil,
      onSelect: { open($0) },
      onCompose: startNewChat, isBesideChat: isBesideChat
    )
    // Beside the chat the list does not reach the trailing edge, yet it is handed the inset of the side strip and the
    // system tab bar there, which left an empty band on the unfolded Duo; the chat column keeps that inset.
    .ignoresSafeArea(.container, edges: isBesideChat ? .trailing : [])
    .sheet(item: $newChat) { search in NewChatScreen(viewModel: search) }
  }

  /// The compose button in the chat list's navigation bar: the new chat sheet, which opens the chat it finds or makes.
  private func startNewChat() {
    newChat = makePeopleSearch(.direct) { roomId, name in
      newChat = nil
      open(
        RoomSummary(
          id: roomId, name: name, lastMessageText: nil, lastMessageSender: nil, lastActivity: nil))
    }
  }

  /// Every chat the user is in, whatever the list's search and filter show.
  static func shareTargets(_ state: ChatListViewModel.State) -> [RoomSummary] {
    guard case .loaded(let rooms) = state else { return [] }
    return rooms.filter { !$0.isInvite }
  }

  /// Waits for the room list to know `roomId` (cold start from a notification or a link), then opens it.
  private func openWhenKnown(_ roomId: String, name: String, at eventId: String? = nil) async {
    let summary =
      await chatList.summary(for: roomId, waitingUpTo: .seconds(10))
      ?? RoomSummary(
        id: roomId, name: name, lastMessageText: nil, lastMessageSender: nil, lastActivity: nil)
    open(summary, at: eventId)
  }

  /// Opens a room; with an event, scrolls to that message once the room shows (a link to a message).
  private func open(_ summary: RoomSummary, at eventId: String? = nil) {
    push.openRoomId = summary.id
    if let room, room.roomId == summary.id {
      if let eventId { Task { await room.jump(toEvent: eventId, maxPages: 50) } }
    } else {
      let made = makeRoom(summary) { [room = $room, pushed = $isRoomPushed] in
        pushed.wrappedValue = false
        room.wrappedValue = nil
      }
      made.pendingEventId = eventId
      made.onFixSession = { [fixing = $isFixingSession] in fixing.wrappedValue = true }
      room = made
    }
    isRoomPushed = true
  }

  /// Once per sign-in: asks, shortly after the first sync had time to report it, whether this session can read
  /// encrypted messages, and offers Privacy & Security when it cannot. The banner in a chat stays for those who
  /// choose Later.
  private func promptForSessionFix() async {
    guard let checkSession else { return }
    for pause in [Duration.seconds(3), .seconds(10)] {
      try? await Task.sleep(for: pause)
      if Task.isCancelled { return }
      if let warning = await checkSession() {
        sessionPrompt = warning
        return
      }
    }
  }
}
