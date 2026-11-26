import DesignSystem
import Domain
import Observation
import SwiftUI

@MainActor @Observable
public final class QuickSwitcherViewModel: Identifiable {
  public enum Option: Identifiable, Equatable {
    case chat(RoomSummary)
    case group(PublicRoom)

    public var id: String {
      switch self {
      case .chat(let room): "chat:\(room.id)"
      case .group(let room): "group:\(room.id)"
      }
    }
  }

  static let shownChats = 12

  public var query = "" {
    didSet {
      guard query != oldValue else { return }
      highlighted = 0
      if term.count >= PublicRoomsViewModel.minimumSearchLength { publicRooms?.query = term }
    }
  }
  public private(set) var highlighted = 0

  public let list: ChatListViewModel
  @ObservationIgnored let publicRooms: PublicRoomsViewModel?
  @ObservationIgnored private let onOpen: @MainActor (RoomSummary) -> Void

  public init(list: ChatListViewModel, onOpen: @escaping @MainActor (RoomSummary) -> Void) {
    self.list = list
    self.onOpen = onOpen
    publicRooms = list.makePublicRooms(onJoined: onOpen)
  }

  private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

  public var chats: [RoomSummary] { Self.rank(list.allJoinedRooms, query: query) }

  public var groups: [PublicRoom] {
    guard term.count >= PublicRoomsViewModel.minimumSearchLength,
      let found = publicRooms?.rooms
    else { return [] }
    let joined = Set(list.allJoinedRooms.map(\.id))
    return found.filter { !joined.contains($0.id) }
  }

  public var options: [Option] { chats.map(Option.chat) + groups.map(Option.group) }

  public var current: Option? {
    let options = options
    guard !options.isEmpty else { return nil }
    return options[min(highlighted, options.count - 1)]
  }

  public var errorMessage: String? { publicRooms?.errorMessage }

  public func isWorking(_ room: PublicRoom) -> Bool {
    publicRooms?.working.contains(room.id) ?? false
  }

  public func isRequested(_ room: PublicRoom) -> Bool {
    publicRooms?.requested.contains(room.id) ?? false
  }

  public func move(by step: Int) {
    let count = options.count
    guard count > 0 else { return }
    let from = min(highlighted, count - 1)
    highlighted = ((from + step) % count + count) % count
  }

  public func openCurrent() async {
    guard let current else { return }
    await open(current)
  }

  public func open(_ option: Option) async {
    switch option {
    case .chat(let room): onOpen(room)
    case .group(let room): await publicRooms?.open(room)
    }
  }

  public func stop() {
    publicRooms?.stop()
  }

  static func rank(_ rooms: [RoomSummary], query: String) -> [RoomSummary] {
    let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let matching = rooms.enumerated().filter { _, room in
      !room.isInvite && !room.isSpace
        && (term.isEmpty
          || room.name.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
    }
    let ranked = matching.sorted { first, second in
      let firstUnread = isUnread(first.element)
      let secondUnread = isUnread(second.element)
      if firstUnread != secondUnread { return firstUnread }
      let firstDate = first.element.lastActivity ?? .distantPast
      let secondDate = second.element.lastActivity ?? .distantPast
      if firstDate != secondDate { return firstDate > secondDate }
      return first.offset < second.offset
    }
    return ranked.prefix(shownChats).map(\.element)
  }

  private static func isUnread(_ room: RoomSummary) -> Bool {
    room.isUnread || room.mentionCount > 0
  }

  nonisolated public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

public struct QuickSwitcherScreen: View {
  @Bindable var viewModel: QuickSwitcherViewModel
  let onClose: () -> Void
  @FocusState private var isFieldFocused: Bool

  public init(viewModel: QuickSwitcherViewModel, onClose: @escaping () -> Void) {
    self.viewModel = viewModel
    self.onClose = onClose
  }

  public var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        List {
          let chats = viewModel.chats
          if !chats.isEmpty {
            Section(localized("Your conversations")) {
              ForEach(chats) { room in
                row(.chat(room)) { ChatListRow(room: room, viewModel: viewModel.list) }
              }
            }
          }
          let groups = viewModel.groups
          if !groups.isEmpty {
            Section(localized("Groups you can join")) {
              ForEach(groups) { room in row(.group(room)) { groupRow(room) } }
            }
          }
          if let message = viewModel.errorMessage {
            Text(message).foregroundStyle(SysColors.error)
          }
        }
        .listStyle(.plain)
        .overlay {
          if viewModel.options.isEmpty, !viewModel.query.isEmpty {
            ContentUnavailableView.search(text: viewModel.query)
          }
        }
        .onChange(of: viewModel.current?.id) { _, id in
          guard let id else { return }
          withAnimation { proxy.scrollTo(id) }
        }
      }
      .safeAreaInset(edge: .top) { field }
      .navigationTitle(localized("Open a chat"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(localized("Close"), action: onClose).keyboardShortcut(.cancelAction)
        }
      }
      .background {
        Button(localized("Close"), action: onClose)
          .keyboardShortcut("k", modifiers: .command)
          .opacity(0)
          .accessibilityHidden(true)
      }
    }
    .onAppear { isFieldFocused = true }
    .onDisappear { viewModel.stop() }
  }

  private var field: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass").foregroundStyle(SysColors.textSecondary)
      TextField(localized("Search a chat or a group"), text: $viewModel.query)
        .focused($isFieldFocused)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.go)
        .onSubmit { Task { await viewModel.openCurrent() } }
        .onKeyPress(.downArrow) {
          viewModel.move(by: 1)
          return .handled
        }
        .onKeyPress(.upArrow) {
          viewModel.move(by: -1)
          return .handled
        }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(SysColors.surface, in: Capsule())
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(SysColors.background)
  }

  private func row(_ option: QuickSwitcherViewModel.Option, content: () -> some View) -> some View {
    Button {
      Task { await viewModel.open(option) }
    } label: {
      content()
    }
    .buttonStyle(.plain)
    .id(option.id)
    .listRowBackground(
      Rectangle().fill(SysColors.primary.opacity(viewModel.current?.id == option.id ? 0.12 : 0)))
  }

  private func groupRow(_ room: PublicRoom) -> some View {
    HStack(spacing: 12) {
      TwakeAvatar(
        name: room.name, size: 52, pictureID: room.avatar?.source,
        load: room.avatar.map { reference in
          { @Sendable [list = viewModel.list] in await list.picture(reference) }
        })
      VStack(alignment: .leading, spacing: 2) {
        Text(room.name).font(.headline).foregroundStyle(SysColors.onSurface).lineLimit(1)
        Text(localized("\(room.memberCount) members"))
          .font(.subheadline)
          .foregroundStyle(SysColors.textSecondary)
      }
      Spacer(minLength: 8)
      groupAction(room)
    }
    .padding(.vertical, 10)
    .contentShape(Rectangle())
  }

  @ViewBuilder private func groupAction(_ room: PublicRoom) -> some View {
    if viewModel.isWorking(room) {
      ProgressView()
    } else if viewModel.isRequested(room) {
      Text(localized("Requested")).font(.subheadline).foregroundStyle(SysColors.textSecondary)
    } else {
      switch room.access {
      case .open:
        Text(localized("Join")).font(.subheadline.weight(.semibold)).foregroundStyle(
          SysColors.primary)
      case .request:
        Text(localized("Ask to join")).font(.subheadline.weight(.semibold)).foregroundStyle(
          SysColors.primary)
      case .inviteOnly:
        Label(localized("Invite only"), systemImage: "lock")
          .font(.caption)
          .foregroundStyle(SysColors.textSecondary)
      }
    }
  }
}

extension View {
  public func quickSwitcher(
    _ switcher: Binding<QuickSwitcherViewModel?>,
    make: @escaping @MainActor () -> QuickSwitcherViewModel
  ) -> some View {
    background {
      Button(localized("Open a chat")) {
        switcher.wrappedValue = switcher.wrappedValue == nil ? make() : nil
      }
      .keyboardShortcut("k", modifiers: .command)
      .opacity(0)
      .accessibilityHidden(true)
    }
    .sheet(item: switcher) { viewModel in
      QuickSwitcherScreen(viewModel: viewModel) { switcher.wrappedValue = nil }
    }
  }
}
