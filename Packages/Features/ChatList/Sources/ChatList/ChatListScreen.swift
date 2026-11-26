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
  @State private var newSpace: NewSpaceViewModel?
  @State private var folderEditor: FolderEditorViewModel?
  @State private var deletingFolder: Folder?
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
          ? (viewModel.selection.isEmpty
            ? localized("Select chats") : localized("\(viewModel.selection.count) selected"))
          : localized("Chats")
      )
      .navigationBarTitleDisplayMode(.large)
      .navigationDestination(item: $openedSpace) { space in
        SpaceScreen(viewModel: space)
          .ignoresSafeArea(.container, edges: isBesideChat ? .trailing : [])
      }
      .searchable(
        text: $viewModel.query, placement: .navigationBarDrawer(displayMode: .always),
        prompt: localized("Search chats and messages")
      )
      .task(id: viewModel.query) { await viewModel.searchMessages() }
      .task { await viewModel.refreshDoNotDisturb() }
      .task { await viewModel.loadFolders() }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active {
          Task { await viewModel.refreshDoNotDisturb() }
          Task { await viewModel.loadFolders() }
        }
      }
      // Select mode starts from a chat's long-press menu, as in Mail and Files; only then does the bar show Done.
      .toolbar {
        if isSelecting {
          ToolbarItem(placement: .confirmationAction) {
            Button(localized("Done")) { endSelecting() }
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
                ? localized("Activity, \(viewModel.mentionTotal) mentions")
                : viewModel.hasActivity
                  ? localized("Activity, unread chats") : localized("Activity"))
          }
          if let onCompose {
            ToolbarItem(placement: .topBarTrailing) {
              Button(localized("New chat"), systemImage: "square.and.pencil", action: onCompose)
                .accessibilityIdentifier(A11yIdentifiers.chatList.newChat)
            }
          }
          ToolbarItem(placement: .topBarTrailing) {
            Menu(localized("More"), systemImage: "ellipsis.circle") {
              MarkAllReadButton(viewModel: viewModel, rooms: viewModel.unreadRooms)
              if viewModel.hasSpaces {
                Button(localized("New Space"), systemImage: "cube") { startNewSpace() }
                  .accessibilityIdentifier(A11yIdentifiers.chatList.newSpace)
              }
            }
            .accessibilityIdentifier(A11yIdentifiers.chatList.more)
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
        leaving.map { localized("Leave \($0.name)?") } ?? "",
        isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } }),
        titleVisibility: .visible
      ) {
        Button(localized("Leave"), role: .destructive) {
          if let room = leaving { Task { await viewModel.leave(room) } }
        }
      } message: {
        Text(localized("You will no longer receive its messages."))
      }
      .task { await viewModel.start() }
      .sheet(item: $newSpace) { model in NewSpaceScreen(viewModel: model) }
      .sheet(item: $folderEditor) { model in FolderEditorScreen(viewModel: model) }
      .confirmationDialog(
        deletingFolder.map { localized("Delete \($0.name)?") } ?? "",
        isPresented: Binding(
          get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } }),
        titleVisibility: .visible
      ) {
        Button(localized("Delete Folder"), role: .destructive) {
          if let folder = deletingFolder { Task { await viewModel.deleteFolder(folder) } }
        }
      } message: {
        Text(localized("Its chats stay in your list."))
      }
  }

  private func editFolder(_ folder: Folder?) {
    folderEditor = viewModel.makeFolderEditor(folder) { folderEditor = nil }
  }

  @ViewBuilder private func folderMenu(_ folder: Folder) -> some View {
    Button(localized("Edit Folder"), systemImage: "pencil") { editFolder(folder) }
    Button(localized("Move Left"), systemImage: "arrow.left") {
      Task { await viewModel.moveFolder(folder, by: -1) }
    }
    Button(localized("Move Right"), systemImage: "arrow.right") {
      Task { await viewModel.moveFolder(folder, by: 1) }
    }
    Divider()
    Button(localized("Delete Folder"), systemImage: "trash", role: .destructive) {
      deletingFolder = folder
    }
  }

  @ViewBuilder private func foldersMenu(_ room: RoomSummary) -> some View {
    if viewModel.hasFolders, !room.isSpace {
      Menu(localized("Folders"), systemImage: "folder") {
        ForEach(viewModel.userFolders) { folder in
          Toggle(
            folder.title,
            isOn: Binding(
              get: { viewModel.isRoom(room, in: folder) },
              set: { _ in Task { await viewModel.toggle(room, in: folder) } }))
        }
        Button(localized("New Folder"), systemImage: "folder.badge.plus") { editFolder(nil) }
      }
    }
  }

  private func startNewSpace() {
    newSpace = viewModel.makeNewSpace { [viewModel, onSelect] summary in
      newSpace = nil
      openedSpace = viewModel.makeSpace(summary, onOpen: { onSelect($0) })
    }
  }

  @ViewBuilder private var content: some View {
    switch viewModel.state {
    case .loading:
      ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    case .empty:
      ContentUnavailableView(
        localized("Welcome to Twake 👋"), systemImage: "bubble.left.and.bubble.right",
        description: Text(localized("Start one with the New chat button.")))
    case .failed(let message):
      ContentUnavailableView(message, systemImage: "exclamationmark.triangle")
    case .loaded:
      if viewModel.showsNoResults {
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
          let isOn = viewModel.filter == filter && viewModel.selectedFolderId == nil
          FilterChip(title: filter.title, isOn: isOn) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
              viewModel.select(filter)
            }
          }
          .accessibilityIdentifier(A11yIdentifiers.chatList.filter(filter.title))
        }
        ForEach(viewModel.userFolders) { folder in
          FilterChip(title: folder.title, isOn: viewModel.selectedFolderId == folder.id) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
              viewModel.selectFolder(folder)
            }
          }
          .accessibilityIdentifier(A11yIdentifiers.chatList.folder(folder.name))
          .contextMenu { folderMenu(folder) }
        }
        if viewModel.hasFolders {
          Button(localized("New Folder"), systemImage: "plus") { editFolder(nil) }
            .labelStyle(.iconOnly)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(SysColors.onSurface)
            .frame(width: 32, height: 32)
            .background(SysColors.surface, in: Circle())
            .buttonStyle(.borderless)
            .accessibilityIdentifier(A11yIdentifiers.chatList.newFolder)
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
      Button(localized("Read"), systemImage: "envelope.open") {
        Task {
          await viewModel.markSelectionRead()
          endSelecting()
        }
      }
      Spacer()
      Button(localized("Mute"), systemImage: "bell.slash") {
        Task {
          await viewModel.toggleSelectionMuted()
          endSelecting()
        }
      }
      Spacer()
      Button(localized("Favourite"), systemImage: "star") {
        Task {
          await viewModel.toggleSelectionFavourite()
          endSelecting()
        }
      }
      Spacer()
      Button(
        localized("Leave"), systemImage: "rectangle.portrait.and.arrow.right", role: .destructive
      ) {
        isConfirmingLeaveSelection = true
      }
      .confirmationDialog(
        localized("Leave \(count == 1 ? "this chat" : "\(count) chats")?"),
        isPresented: $isConfirmingLeaveSelection, titleVisibility: .visible
      ) {
        Button(localized("Leave"), role: .destructive) {
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
        sectionHeader(localized("Favourites"))
      }
    }
    Section {
      ForEach(viewModel.filter == .favourites ? favourites : viewModel.otherRooms) { room in
        row(room)
      }
    } header: {
      if !favourites.isEmpty, viewModel.filter != .favourites { sectionHeader(localized("Chats")) }
    }
    let lowPriority = viewModel.lowPriorityRooms
    if !lowPriority.isEmpty, viewModel.filter != .favourites {
      Section {
        ForEach(lowPriority) { room in row(room) }
      } header: {
        sectionHeader(localized("Low priority"))
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
            Label(localized("Public groups"), systemImage: "person.3")
              .foregroundStyle(SysColors.textSecondary)
          }
        }
        if let saved = viewModel.saved {
          NavigationLink {
            SavedMessagesScreen(repository: saved)
              .ignoresSafeArea(.container, edges: isBesideChat ? .trailing : [])
          } label: {
            Label(localized("Saved messages"), systemImage: "bookmark")
              .foregroundStyle(SysColors.textSecondary)
          }
        }
        if let archive = viewModel.makeArchive() {
          NavigationLink {
            ArchivedChatsScreen(viewModel: archive, list: viewModel, onSelect: onSelect)
              .ignoresSafeArea(.container, edges: isBesideChat ? .trailing : [])
          } label: {
            Label(localized("Archived chats"), systemImage: "archivebox")
              .foregroundStyle(SysColors.textSecondary)
          }
        }
      }
    }
    if viewModel.joinedRooms.isEmpty {
      Text(localized("No chats here."))
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

  private func open(_ room: RoomSummary) {
    if let space = viewModel.makeSpace(room, onOpen: { [onSelect] in onSelect($0) }) {
      openedSpace = space
    } else {
      onSelect(room)
    }
  }

  private func roomButton(_ room: RoomSummary) -> some View {
    Button {
      open(room)
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
      Button(
        localized("Leave"), systemImage: "rectangle.portrait.and.arrow.right", role: .destructive
      ) {
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
    Button(localized("Open"), systemImage: "arrow.up.forward.app") { open(room) }
    Button(localized("Select"), systemImage: "checkmark.circle") {
      withAnimation {
        isSelecting = true
        viewModel.selection = [room.id]
      }
    }
    Divider()
    readButton(room)
    favouriteButton(room)
    muteButton(room)
    foldersMenu(room)
    Button(
      room.isLowPriority ? localized("Normal priority") : localized("Low priority"),
      systemImage: room.isLowPriority ? "arrow.up.circle" : "arrow.down.circle"
    ) {
      Task { await viewModel.setLowPriority(!room.isLowPriority, room: room) }
    }
    Divider()
    Button(
      localized("Leave"), systemImage: "rectangle.portrait.and.arrow.right", role: .destructive
    ) {
      leaving = room
    }
  }

  private func readButton(_ room: RoomSummary) -> some View {
    let isUnread = room.isUnread
    return Button(
      isUnread ? localized("Read") : localized("Unread"),
      systemImage: isUnread ? "envelope.open" : "envelope.badge"
    ) {
      Task { await viewModel.setUnread(!isUnread, room: room) }
    }
  }

  private func muteButton(_ room: RoomSummary) -> some View {
    Button(
      room.isMuted ? localized("Unmute") : localized("Mute"),
      systemImage: room.isMuted ? "bell" : "bell.slash"
    ) {
      Task { await viewModel.setMuted(!room.isMuted, room: room) }
    }
  }

  private func favouriteButton(_ room: RoomSummary) -> some View {
    Button(
      room.isFavourite ? localized("Unfavourite") : localized("Favourite"),
      systemImage: room.isFavourite ? "star.slash" : "star"
    ) {
      Task { await viewModel.setFavourite(!room.isFavourite, room: room) }
    }
  }
}
