import DesignSystem
import Domain
import SwiftUI

/// The chats, as a native iOS list: the large "Chats" title, the system search field (it filters by name), the
/// invitations folded into one row, favourites first, then the other chats by latest activity. Swipe a chat right to
/// mark it read or unread, left to favourite it or leave it; a long press offers the same. Activity and New chat are
/// toolbar buttons, so iOS places them: in the navigation bar on a phone, in the side rail on the unfolded Duo, as
/// Photos and Mail do. The open room is highlighted when the list sits beside it. It holds no logic.
public struct ChatListScreen: View {
  @Bindable var viewModel: ChatListViewModel
  let selectedRoomId: String?
  let onSelect: (RoomSummary) -> Void
  let onCompose: (() -> Void)?
  /// The list sits beside the open chat: a page pushed over it drops the trailing inset the list drops too.
  let isBesideChat: Bool
  @State private var showsInvites = false
  @State private var leaving: RoomSummary?
  @State private var isSelecting = false
  @State private var isConfirmingLeaveSelection = false
  /// The space opened from the list, pushed over it.
  @State private var openedSpace: SpaceViewModel?
  @State private var connectivity = Connectivity()
  @Environment(\.scenePhase) private var scenePhase

  public init(
    viewModel: ChatListViewModel, selectedRoomId: String? = nil,
    onSelect: @escaping (RoomSummary) -> Void = { _ in }, onCompose: (() -> Void)? = nil,
    isBesideChat: Bool = false
  ) {
    self.isBesideChat = isBesideChat
    self.viewModel = viewModel
    self.selectedRoomId = selectedRoomId
    self.onSelect = onSelect
    self.onCompose = onCompose
  }

  public var body: some View {
    content
      .background(SysColors.background)
      .navigationTitle(
        isSelecting
          ? (viewModel.selection.isEmpty ? "Select chats" : "\(viewModel.selection.count) selected")
          : "Chats"
      )
      .navigationBarTitleDisplayMode(.large)
      .navigationDestination(item: $openedSpace) { space in
        SpaceScreen(viewModel: space)
          .ignoresSafeArea(.container, edges: isBesideChat ? .trailing : [])
      }
      .searchable(
        text: $viewModel.query, placement: .navigationBarDrawer(displayMode: .always),
        prompt: "Search chats and messages"
      )
      .task(id: viewModel.query) { await viewModel.searchMessages() }
      .task { await viewModel.refreshDoNotDisturb() }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { Task { await viewModel.refreshDoNotDisturb() } }
      }
      // Select mode starts from a chat's long-press menu, as in Mail and Files; only then does the bar show Done.
      .toolbar {
        if isSelecting {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { endSelecting() }
          }
        } else {
          ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
              ActivityScreen(viewModel: viewModel, onSelect: onSelect)
                .ignoresSafeArea(.container, edges: isBesideChat ? .trailing : [])
            } label: {
              Image(systemName: viewModel.hasActivity ? "bell.badge.fill" : "bell")
                .symbolEffect(.bounce, value: viewModel.mentionTotal)
                .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(
              viewModel.mentionTotal > 0
                ? "Activity, \(viewModel.mentionTotal) mentions"
                : viewModel.hasActivity ? "Activity, unread chats" : "Activity")
          }
          if let onCompose {
            ToolbarItem(placement: .topBarTrailing) {
              Button("New chat", systemImage: "square.and.pencil", action: onCompose)
            }
          }
          ToolbarItem(placement: .topBarTrailing) {
            Menu("More", systemImage: "ellipsis.circle") {
              MarkAllReadButton(viewModel: viewModel, rooms: viewModel.unreadRooms)
            }
          }
        }
      }
      .environment(\.editMode, .constant(isSelecting ? .active : .inactive))
      .safeAreaInset(edge: .bottom) {
        if isSelecting { selectionBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
      }
      .safeAreaInset(edge: .bottom) {
        if let message = viewModel.logOutErrorMessage ?? viewModel.inviteErrorMessage
          ?? viewModel.actionErrorMessage
        {
          Text(message).foregroundStyle(SysColors.error).padding()
        }
      }
      .confirmationDialog(
        leaving.map { "Leave \($0.name)?" } ?? "",
        isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } }),
        titleVisibility: .visible
      ) {
        Button("Leave", role: .destructive) {
          if let room = leaving { Task { await viewModel.leave(room) } }
        }
      } message: {
        Text("You will no longer receive its messages.")
      }
      .task { await viewModel.start() }
  }

  @ViewBuilder private var content: some View {
    switch viewModel.state {
    case .loading:
      ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    case .empty:
      ContentUnavailableView(
        "Welcome to Twake 👋", systemImage: "bubble.left.and.bubble.right",
        description: Text("Start one with the New chat button."))
    case .failed(let message):
      ContentUnavailableView(message, systemImage: "exclamationmark.triangle")
    case .loaded:
      if viewModel.visibleRooms.isEmpty {
        ContentUnavailableView.search(text: viewModel.query)
      } else {
        list
      }
    }
  }

  /// The filter chips, as Messages and Telegram show them above the chats.
  private var filterBar: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(ChatListViewModel.Filter.allCases) { filter in
          let isOn = viewModel.filter == filter
          Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
              viewModel.filter = filter
            }
          } label: {
            Text(filter.title)
              .font(.subheadline.weight(.medium))
              .foregroundStyle(isOn ? SysColors.onPrimary : SysColors.onSurface)
              .padding(.horizontal, 14)
              .padding(.vertical, 7)
              .background(isOn ? SysColors.primary : SysColors.surface, in: Capsule())
          }
          // Several buttons in one list row each need their own tap: a borderless style keeps them apart.
          .buttonStyle(.borderless)
          .accessibilityAddTraits(isOn ? .isSelected : [])
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 4)
    }
    .scrollIndicators(.hidden)
  }

  private func endSelecting() {
    withAnimation {
      isSelecting = false
      viewModel.selection = []
    }
  }

  /// The actions on the picked chats.
  private var selectionBar: some View {
    let count = viewModel.selection.count
    return HStack {
      Button("Read", systemImage: "envelope.open") {
        Task {
          await viewModel.markSelectionRead()
          endSelecting()
        }
      }
      Spacer()
      Button("Mute", systemImage: "bell.slash") {
        Task {
          await viewModel.toggleSelectionMuted()
          endSelecting()
        }
      }
      Spacer()
      Button("Favourite", systemImage: "star") {
        Task {
          await viewModel.toggleSelectionFavourite()
          endSelecting()
        }
      }
      Spacer()
      Button("Leave", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
        isConfirmingLeaveSelection = true
      }
      .confirmationDialog(
        "Leave \(count == 1 ? "this chat" : "\(count) chats")?",
        isPresented: $isConfirmingLeaveSelection, titleVisibility: .visible
      ) {
        Button("Leave", role: .destructive) {
          Task {
            await viewModel.leaveSelection()
            endSelecting()
          }
        }
      }
    }
    .labelStyle(StackedLabelStyle())
    .disabled(count == 0)
    .padding(.horizontal, 24)
    .padding(.vertical, 12)
    .background(.bar)
  }

  /// The chips above the list; only Select mode gives the list a selection, since a list with one takes over row taps
  /// on a wide screen.
  private var list: some View {
    VStack(spacing: 0) {
      if connectivity.isOffline { OfflineBanner() }
      if viewModel.isDoNotDisturbOn {
        DoNotDisturbBanner { Task { await viewModel.turnOffDoNotDisturb() } }
      }
      filterBar
      if isSelecting {
        List(selection: $viewModel.selection) { listContent }
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
      } else {
        List { listContent }
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
          .accessibilityIdentifier(A11yIdentifiers.chatList.list)
      }
    }
    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.visibleRooms)
  }

  /// A section title that stays at the top while its rows scroll. It fills its row with the screen's background: the
  /// list's own background is hidden, and a clear header let the rows show through the title.
  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(SysColors.textSecondary)
      .lineLimit(1)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 6)
      .background(SysColors.background)
      .listRowInsets(EdgeInsets())
  }

  @ViewBuilder private var listContent: some View {
    let invites = viewModel.invites
    if !invites.isEmpty, viewModel.filter == .all {
      Section {
        InvitesHeader(invites: invites, isExpanded: showsInvites, viewModel: viewModel) {
          withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showsInvites.toggle() }
        }
        .listRowInsets(EdgeInsets())
        if showsInvites {
          ForEach(invites) { room in
            InviteRow(room: room, viewModel: viewModel).listRowInsets(EdgeInsets())
          }
        }
      }
    }
    let favourites = viewModel.favouriteRooms
    if !favourites.isEmpty, viewModel.filter != .favourites {
      Section {
        ForEach(favourites) { room in row(room) }
      } header: {
        sectionHeader("Favourites")
      }
    }
    Section {
      ForEach(viewModel.filter == .favourites ? favourites : viewModel.otherRooms) { room in
        row(room)
      }
    } header: {
      if !favourites.isEmpty, viewModel.filter != .favourites { sectionHeader("Chats") }
    }
    let lowPriority = viewModel.lowPriorityRooms
    if !lowPriority.isEmpty, viewModel.filter != .favourites {
      Section {
        ForEach(lowPriority) { room in row(room) }
      } header: {
        sectionHeader("Low priority")
      }
    }
    if !viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty, !isSelecting {
      MessageResultsSection(viewModel: viewModel)
    }
    if viewModel.filter == .all, !isSelecting {
      Section {
        if let publicRooms = viewModel.makePublicRooms(onJoined: { [onSelect] in onSelect($0) }) {
          NavigationLink {
            PublicRoomsScreen(viewModel: publicRooms, list: viewModel)
              .ignoresSafeArea(.container, edges: isBesideChat ? .trailing : [])
          } label: {
            Label("Public groups", systemImage: "person.3")
              .foregroundStyle(SysColors.textSecondary)
          }
        }
        if let saved = viewModel.saved {
          NavigationLink {
            SavedMessagesScreen(repository: saved)
              .ignoresSafeArea(.container, edges: isBesideChat ? .trailing : [])
          } label: {
            Label("Saved messages", systemImage: "bookmark")
              .foregroundStyle(SysColors.textSecondary)
          }
        }
        if let archive = viewModel.makeArchive() {
          NavigationLink {
            ArchivedChatsScreen(viewModel: archive, list: viewModel, onSelect: onSelect)
              .ignoresSafeArea(.container, edges: isBesideChat ? .trailing : [])
          } label: {
            Label("Archived chats", systemImage: "archivebox")
              .foregroundStyle(SysColors.textSecondary)
          }
        }
      }
    }
    if viewModel.joinedRooms.isEmpty {
      Text("No chats here.")
        .foregroundStyle(SysColors.textSecondary)
        .frame(maxWidth: .infinity)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
  }

  @ViewBuilder private func row(_ room: RoomSummary) -> some View {
    if isSelecting {
      // In Select mode the list itself picks the row and draws the check.
      ChatListRow(room: room, viewModel: viewModel).tag(room.id)
    } else {
      roomButton(room)
    }
  }

  private func roomButton(_ room: RoomSummary) -> some View {
    Button {
      if let space = viewModel.makeSpace(room, onOpen: { [onSelect] in onSelect($0) }) {
        openedSpace = space
      } else {
        onSelect(room)
      }
    } label: {
      ChatListRow(room: room, viewModel: viewModel)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(A11yIdentifiers.chatList.room(room.name))
    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    .listRowBackground(
      Rectangle().fill(
        room.id == selectedRoomId ? SysColors.secondaryContainer : ColorToken(0x0000_0000))
    )
    .swipeActions(edge: .leading, allowsFullSwipe: true) {
      readButton(room).tint(SysColors.primary)
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button("Leave", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
        leaving = room
      }
      favouriteButton(room).tint(.orange)
      muteButton(room).tint(.indigo)
    }
    // A pointer on iPad highlights the row; a secondary click opens the same menu and preview.
    .hoverEffect(.highlight)
    .modifier(
      RoomContextMenu(
        room: room, viewModel: viewModel, menu: { menuItems(room) },
        hasPreview: viewModel.hasPreview(room)))
  }

  /// The long-press menu of a chat row.
  @ViewBuilder private func menuItems(_ room: RoomSummary) -> some View {
    Button("Select", systemImage: "checkmark.circle") {
      withAnimation {
        isSelecting = true
        viewModel.selection = [room.id]
      }
    }
    Divider()
    readButton(room)
    favouriteButton(room)
    muteButton(room)
    Button(
      room.isLowPriority ? "Normal priority" : "Low priority",
      systemImage: room.isLowPriority ? "arrow.up.circle" : "arrow.down.circle"
    ) {
      Task { await viewModel.setLowPriority(!room.isLowPriority, room: room) }
    }
    Divider()
    Button("Leave", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
      leaving = room
    }
  }

  private func readButton(_ room: RoomSummary) -> some View {
    let isUnread = room.isUnread
    return Button(
      isUnread ? "Read" : "Unread",
      systemImage: isUnread ? "envelope.open" : "envelope.badge"
    ) {
      Task { await viewModel.setUnread(!isUnread, room: room) }
    }
  }

  private func muteButton(_ room: RoomSummary) -> some View {
    Button(
      room.isMuted ? "Unmute" : "Mute", systemImage: room.isMuted ? "bell" : "bell.slash"
    ) {
      Task { await viewModel.setMuted(!room.isMuted, room: room) }
    }
  }

  private func favouriteButton(_ room: RoomSummary) -> some View {
    Button(
      room.isFavourite ? "Unfavourite" : "Favourite",
      systemImage: room.isFavourite ? "star.slash" : "star"
    ) {
      Task { await viewModel.setFavourite(!room.isFavourite, room: room) }
    }
  }
}

/// One chat, as Messages lays it out: the picture, the name in bold while unread, the time on the right, and two lines
/// of the last message with the unread count under the time.
struct ChatListRow: View {
  let room: RoomSummary
  let viewModel: ChatListViewModel

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      RoomAvatar(room: room, viewModel: viewModel, size: 52)
        .overlay(alignment: .bottomTrailing) {
          if let dot = viewModel.presenceDot(of: room) {
            AvatarPresenceDot(AvatarPresence(dot), avatarSize: 52).offset(x: 2, y: 2)
          }
        }
        .task(id: room.directUserId) { await viewModel.refreshPresence(of: room) }
      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline) {
          Text(room.name)
            .font(.headline.weight(room.isUnread ? .bold : .semibold))
            .foregroundStyle(SysColors.onSurface)
            .lineLimit(1)
          if room.isEncrypted {
            Image(systemName: "lock.fill").font(.caption2).foregroundStyle(SysColors.textSecondary)
              .accessibilityLabel("Encrypted")
          }
          if room.isFavourite {
            Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange)
          }
          if room.isMuted {
            Image(systemName: "bell.slash.fill").font(.caption2).foregroundStyle(
              SysColors.textSecondary
            )
            .accessibilityLabel("Muted")
          }
          Spacer(minLength: 4)
          if let date = room.lastActivity {
            Text(ChatListViewModel.timeText(date))
              .font(.subheadline)
              .foregroundStyle(room.isUnread ? SysColors.primary : SysColors.textSecondary)
          }
        }
        HStack(alignment: .top) {
          Group {
            // Who types comes first, then the draft (web `RoomList.tsx`).
            if let typing = ChatListViewModel.typingLine(of: room) {
              Text(typing).foregroundStyle(SysColors.primary)
            } else if let draft = room.draft, !room.isSpace {
              Text("\(Text("Draft:").foregroundStyle(SysColors.error)) \(draft)")
                .foregroundStyle(SysColors.textSecondary)
            } else if !room.isSpace, let state = room.lastMessageSendState,
              let preview = ChatListViewModel.preview(of: room)
            {
              // No mark beside an event the row cannot name: a tick stood alone on a blank line.
              Text("\(SendStateMark(state: state).image) \(preview)")
                .foregroundStyle(SysColors.textSecondary)
            } else {
              Text(room.isSpace ? "Space" : ChatListViewModel.preview(of: room) ?? " ")
                .foregroundStyle(SysColors.textSecondary)
            }
          }
          .font(.subheadline)
          .lineLimit(2, reservesSpace: true)
          .contentTransition(.opacity)
          .animation(.easeInOut(duration: 0.25), value: room.draft)
          Spacer(minLength: 4)
          UnreadBadge(
            unread: room.unreadCount, mentions: room.mentionCount, isMuted: room.isMuted,
            isMarkedUnread: room.isMarkedUnread)
        }
      }
      // The separator starts under the text, as in Messages.
      .alignmentGuide(.listRowSeparatorLeading) { dimensions in dimensions[.leading] }
    }
    .padding(.vertical, 10)
    .contentShape(Rectangle())
  }
}

/// The unread count of a room, as the Flutter chat list shows it: "@" for a mention, then the count in a `primary`
/// capsule. A new count pops and rolls to its value.
struct UnreadBadge: View {
  let unread: Int
  let mentions: Int
  /// A muted room's count is grey, as in Messages and WhatsApp: it is unread, but nothing asks for attention.
  var isMuted = false
  /// The user marked the room as unread: a dot when no message is unread, as the Flutter chat list shows it.
  var isMarkedUnread = false

  private var fill: ColorToken { isMuted ? SysColors.textSecondary : SysColors.primary }

  var body: some View {
    HStack(spacing: 4) {
      if mentions > 0 {
        Text("@")
          .textStyle(TextStyles.labelMedium)
          .foregroundStyle(SysColors.onPrimary)
          .frame(width: 20, height: 20)
          .background(fill, in: Circle())
          .transition(.scale.combined(with: .opacity))
      }
      if unread > 0 {
        Text(unread > 999 ? "999+" : "\(unread)")
          .textStyle(TextStyles.labelMedium)
          .foregroundStyle(SysColors.onPrimary)
          .contentTransition(.numericText(value: Double(unread)))
          .padding(.horizontal, 6)
          .frame(minWidth: 20, minHeight: 20)
          .background(fill, in: Capsule())
          .transition(.scale.combined(with: .opacity))
      } else if isMarkedUnread, mentions == 0 {
        Circle().fill(fill).frame(width: 12, height: 12)
          .accessibilityLabel("Marked as unread")
          .transition(.scale.combined(with: .opacity))
      }
    }
    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: unread)
    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: mentions)
  }
}

/// The send state of the user's own last message before its text on the row: a clock while it is sent, a tick once
/// sent, a red mark when it failed (Flutter `chat_list_item_subtitle.dart`). The SDK's latest event says nothing about
/// who read it, so the row has no "read" mark.
struct SendStateMark {
  let state: RoomSummary.SendState

  var image: Text {
    switch state {
    case .sending: Text(Image(systemName: "clock")).accessibilityLabel("Sending")
    case .sent: Text(Image(systemName: "checkmark")).accessibilityLabel("Sent")
    case .failed:
      Text(Image(systemName: "exclamationmark.circle.fill")).foregroundStyle(SysColors.error)
        .accessibilityLabel("Not sent")
    }
  }
}

/// A room's picture, or its initial while the picture loads or when it has none.
struct RoomAvatar: View {
  let room: RoomSummary
  let viewModel: ChatListViewModel
  var size: CGFloat = 56

  var body: some View {
    let reference = room.avatar
    TwakeAvatar(
      name: room.name, size: size, pictureID: reference?.source,
      load: reference.map { reference in
        { @Sendable [viewModel] in await viewModel.picture(reference) }
      })
  }
}

/// The invitations, folded into one row as Telegram folds archived chats: up to three stacked pictures, "Invitations"
/// with how many, and a chevron that opens or closes the section.
struct InvitesHeader: View {
  let invites: [RoomSummary]
  let isExpanded: Bool
  let viewModel: ChatListViewModel
  let toggle: () -> Void

  var body: some View {
    Button(action: toggle) {
      HStack(spacing: 12) {
        ZStack(alignment: .leading) {
          ForEach(Array(invites.prefix(3).enumerated()), id: \.element.id) { index, room in
            RoomAvatar(room: room, viewModel: viewModel, size: 32)
              .overlay(Circle().strokeBorder(SysColors.background, lineWidth: 2))
              .offset(x: CGFloat(index) * 14)
          }
        }
        .frame(width: 56, alignment: .leading)
        Text("Invitations")
          .textStyle(TextStyles.titleMedium.with(weight: .semibold))
          .foregroundStyle(SysColors.onSurface)
        Text("\(invites.count)")
          .textStyle(TextStyles.labelMedium)
          .foregroundStyle(SysColors.onPrimary)
          .padding(.horizontal, 7)
          .frame(minWidth: 22, minHeight: 22)
          .background(SysColors.primary, in: Capsule())
        Spacer(minLength: 8)
        Image(systemName: "chevron.right")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(SysColors.textSecondary)
          .rotationEffect(.degrees(isExpanded ? 90 : 0))
      }
      .padding(.horizontal, 16)
      .frame(height: 56)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(invites.count) invitations")
    .accessibilityValue(isExpanded ? "Shown" : "Hidden")
  }
}

/// An invitation: the room, "Invited you to chat", and two round buttons, decline and accept, at the trailing edge.
struct InviteRow: View {
  let room: RoomSummary
  let viewModel: ChatListViewModel

  var body: some View {
    let isAnswering = viewModel.answering.contains(room.id)
    HStack(spacing: 12) {
      RoomAvatar(room: room, viewModel: viewModel, size: 48)
      VStack(alignment: .leading, spacing: 2) {
        Text(room.name)
          .textStyle(TextStyles.titleMedium)
          .foregroundStyle(SysColors.onSurface)
          .lineLimit(1)
        Text("Invited you to chat")
          .textStyle(TextStyles.bodySmall)
          .foregroundStyle(SysColors.textSecondary)
          .lineLimit(1)
      }
      Spacer(minLength: 8)
      if isAnswering {
        ProgressView().frame(width: 80)
      } else {
        Button {
          Task { await viewModel.answerInvite(room, accept: false) }
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(SysColors.onSurface)
            .frame(width: 34, height: 34)
            .background(SysColors.surface, in: Circle())
        }
        .accessibilityLabel("Decline \(room.name)")
        Button {
          Task { await viewModel.answerInvite(room, accept: true) }
        } label: {
          Image(systemName: "checkmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(SysColors.onPrimary)
            .frame(width: 34, height: 34)
            .background(SysColors.primary, in: Circle())
        }
        .accessibilityLabel("Accept \(room.name)")
      }
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 16)
    .frame(height: 64)
  }
}

/// An icon above a small title, as the toolbars of Mail and Photos lay out several actions side by side.
struct StackedLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(spacing: 3) {
      configuration.icon.font(.system(size: 19))
      configuration.title.font(.caption2)
    }
    .frame(minWidth: 52)
  }
}

/// The messages the server found for the search text, under the matching chats: the chat, the sender and the text; a
/// tap opens the chat at that message.
struct MessageResultsSection: View {
  let viewModel: ChatListViewModel
  @Environment(\.openURL) private var openURL

  var body: some View {
    if !viewModel.peopleResults.isEmpty {
      Section("People") {
        ForEach(viewModel.peopleResults) { person in
          Button {
            Task { await viewModel.open(person) }
          } label: {
            HStack(spacing: 12) {
              TwakeAvatar(name: person.name, size: 36)
              VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(person.id).font(.caption).foregroundStyle(SysColors.textSecondary)
                  .lineLimit(1)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .transition(.opacity.combined(with: .move(edge: .top)))
        }
      }
    }
    Section {
      if viewModel.isSearchingMessages, viewModel.messageResults.isEmpty {
        HStack {
          Spacer()
          ProgressView()
          Spacer()
        }
      }
      ForEach(viewModel.messageResults) { result in
        Button {
          if let roomId = result.roomId,
            let url = MatrixLink.room(idOrAlias: roomId, eventId: result.eventId, via: []).url
          {
            openURL(url)
          }
        } label: {
          VStack(alignment: .leading, spacing: 3) {
            HStack {
              Text(viewModel.room(of: result)?.name ?? "")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
              Spacer()
              Text(ChatListViewModel.timeText(result.date))
                .font(.caption)
                .foregroundStyle(SysColors.textSecondary)
            }
            Text("\(Text(result.senderName).bold()): \(result.text)")
              .font(.subheadline)
              .foregroundStyle(SysColors.textSecondary)
              .lineLimit(2)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    } header: {
      if viewModel.isSearchingMessages || !viewModel.messageResults.isEmpty {
        Text("Messages")
      }
    } footer: {
      if !viewModel.messageResults.isEmpty {
        Text("Messages in encrypted chats are searched inside each chat.")
      }
    }
  }
}
