import DesignSystem
import Domain
import SwiftUI

/// The chats, as a native iOS list: the large "Chats" title, the system search field (it filters by name), the
/// invitations folded into one row, favourites first, then the other chats by latest activity. Swipe a chat right to
/// mark it read or unread, left to favourite it or leave it; a long press offers the same. The compose button floats at
/// the bottom corner, under the thumb. The open room is highlighted when the list sits beside it. It holds no logic.
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
  /// The space opened from the list, pushed over it.
  @State private var openedSpace: SpaceViewModel?

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
        prompt: "Search"
      )
      // Select mode starts from a chat's long-press menu, as in Mail and Files; only then does the bar show Done.
      .toolbar {
        if isSelecting {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { endSelecting() }
          }
        }
      }
      .environment(\.editMode, .constant(isSelecting ? .active : .inactive))
      .overlay(alignment: .bottomTrailing) {
        if let onCompose, !isSelecting {
          TwakeFloatingButton("New chat", systemImage: "square.and.pencil", action: onCompose)
            .transition(.scale.combined(with: .opacity))
        }
      }
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
        "No chats yet", systemImage: "bubble.left.and.bubble.right",
        description: Text("Start one with the compose button."))
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
    }
    .labelStyle(.titleAndIcon)
    .disabled(count == 0)
    .padding(.horizontal, 24)
    .padding(.vertical, 12)
    .background(.bar)
  }

  /// The chips above the list; only Select mode gives the list a selection, since a list with one takes over row taps
  /// on a wide screen.
  private var list: some View {
    VStack(spacing: 0) {
      filterBar
      if isSelecting {
        List(selection: $viewModel.selection) { listContent }
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
      } else {
        List { listContent }
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
          // The last chat scrolls clear of the floating compose button.
          .contentMargins(.bottom, onCompose == nil ? 0 : 80, for: .scrollContent)
      }
    }
    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.visibleRooms)
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
      Section("Favourites") {
        ForEach(favourites) { room in row(room) }
      }
    }
    Section(favourites.isEmpty || viewModel.filter == .favourites ? "" : "Chats") {
      ForEach(viewModel.filter == .favourites ? favourites : viewModel.otherRooms) { room in
        row(room)
      }
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
    .contextMenu {
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
      Divider()
      Button("Leave", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
        leaving = room
      }
    }
  }

  private func readButton(_ room: RoomSummary) -> some View {
    let isUnread = room.unreadCount > 0
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
      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline) {
          Text(room.name)
            .font(.headline.weight(room.unreadCount > 0 ? .bold : .semibold))
            .foregroundStyle(SysColors.onSurface)
            .lineLimit(1)
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
              .foregroundStyle(room.unreadCount > 0 ? SysColors.primary : SysColors.textSecondary)
          }
        }
        HStack(alignment: .top) {
          Text(room.isSpace ? "Space" : ChatListViewModel.preview(of: room) ?? " ")
            .font(.subheadline)
            .foregroundStyle(SysColors.textSecondary)
            .lineLimit(2, reservesSpace: true)
          Spacer(minLength: 4)
          UnreadBadge(unread: room.unreadCount, mentions: room.mentionCount)
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

  var body: some View {
    HStack(spacing: 4) {
      if mentions > 0 {
        Text("@")
          .textStyle(TextStyles.labelMedium)
          .foregroundStyle(SysColors.onPrimary)
          .frame(width: 20, height: 20)
          .background(SysColors.primary, in: Circle())
          .transition(.scale.combined(with: .opacity))
      }
      if unread > 0 {
        Text(unread > 999 ? "999+" : "\(unread)")
          .textStyle(TextStyles.labelMedium)
          .foregroundStyle(SysColors.onPrimary)
          .contentTransition(.numericText(value: Double(unread)))
          .padding(.horizontal, 6)
          .frame(minWidth: 20, minHeight: 20)
          .background(SysColors.primary, in: Capsule())
          .transition(.scale.combined(with: .opacity))
      }
    }
    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: unread)
    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: mentions)
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
