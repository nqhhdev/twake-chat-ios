import DesignSystem
import Domain
import Observation
import SwiftUI

/// A space (Flutter `space_home`): its rooms and sub-spaces. A room the user is in opens; another is joined first,
/// through the servers the space lists; a sub-space opens as its own page.
@MainActor @Observable
public final class SpaceViewModel {
  public let space: RoomSummary
  /// `nil` until loaded.
  public private(set) var children: [SpaceChild]?
  public private(set) var errorMessage: String?
  public private(set) var joining: Set<String> = []

  @ObservationIgnored private let repository: any SpacesRepository
  @ObservationIgnored private let onOpen: @MainActor (RoomSummary) -> Void
  @ObservationIgnored let picture: @Sendable (MediaReference) async -> Data?
  /// Marks one room read; `nil` hides "Mark All as Read".
  @ObservationIgnored let markRead: (@MainActor (String) async -> Void)?
  public private(set) var isMarkingRead = false
  /// The user may add rooms to this space.
  public private(set) var canAddChannel = false
  public private(set) var isCreating = false
  /// The look the web gives the space (`app.twake.chat.page_style`), drawn as the header; `nil` draws the plain one.
  public private(set) var pageStyle: PageStyle?
  /// The look of each Broadcast of the space that has one, by room id.
  public private(set) var childStyles: [String: PageStyle] = [:]

  public init(
    space: RoomSummary, repository: any SpacesRepository,
    picture: @escaping @Sendable (MediaReference) async -> Data?,
    onOpen: @escaping @MainActor (RoomSummary) -> Void,
    markRead: (@MainActor (String) async -> Void)? = nil
  ) {
    self.markRead = markRead
    self.space = space
    self.repository = repository
    self.picture = picture
    self.onOpen = onOpen
  }

  public func load() async {
    errorMessage = nil
    canAddChannel = await repository.canAddChannel(to: space.id)
    pageStyle = await repository.pageStyle(of: space.id)
    do {
      let found = try await repository.children(of: space.id)
      // Sub-spaces first, then rooms; joined ones before the others; by name.
      children = found.sorted { lhs, rhs in
        if lhs.isSpace != rhs.isSpace { return lhs.isSpace }
        if lhs.isJoined != rhs.isJoined { return lhs.isJoined }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
      }
    } catch {
      children = children ?? []
      errorMessage = "Could not load this space."
    }
    await loadChildStyles()
  }

  /// Reads the page style of the Broadcasts listed, at most `maxStyledChildren` of them, all at once.
  private func loadChildStyles() async {
    let ids = (children ?? []).filter(\.isBroadcast).prefix(Self.maxStyledChildren).map(\.id)
    let repository = repository
    childStyles = await withTaskGroup(of: (String, PageStyle?).self) { group in
      for id in ids { group.addTask { (id, await repository.pageStyle(of: id)) } }
      var found: [String: PageStyle] = [:]
      for await (id, style) in group { found[id] = style }
      return found
    }
  }

  /// Broadcasts whose style is read, so a huge space does not send a request per room.
  static let maxStyledChildren = 20

  /// Joins a sub-space the user is not in, so it reaches the chat list (Flutter's joinable sub-space row). It stays
  /// on this screen; opening it is a tap on the row.
  public func join(subspace child: SpaceChild) async {
    guard child.isSpace, !child.isJoined, !joining.contains(child.id) else { return }
    joining.insert(child.id)
    defer { joining.remove(child.id) }
    errorMessage = nil
    do {
      _ = try await repository.join(child)
    } catch {
      errorMessage = "Could not join \(child.name). It may need an invitation."
      return
    }
    if let index = children?.firstIndex(where: { $0.id == child.id }) {
      children?[index] = SpaceChild(
        id: child.id, name: child.name, topic: child.topic, avatar: child.avatar,
        memberCount: child.memberCount, isJoined: true, isSpace: true, via: child.via,
        isBroadcast: child.isBroadcast)
    }
  }

  /// Opens a room of the space, joining it first when the user is not in it.
  public func open(_ child: SpaceChild) async {
    guard !child.isSpace, !joining.contains(child.id) else { return }
    var roomId = child.id
    if !child.isJoined {
      joining.insert(child.id)
      defer { joining.remove(child.id) }
      errorMessage = nil
      do {
        roomId = try await repository.join(child)
      } catch {
        errorMessage = "Could not join \(child.name). It may need an invitation."
        return
      }
      if let index = children?.firstIndex(where: { $0.id == child.id }) {
        children?[index] = SpaceChild(
          id: child.id, name: child.name, topic: child.topic, avatar: child.avatar,
          memberCount: child.memberCount, isJoined: true, isSpace: false, via: child.via,
          isBroadcast: child.isBroadcast)
      }
    }
    onOpen(
      RoomSummary(
        id: roomId, name: child.name, lastMessageText: nil, lastMessageSender: nil,
        lastActivity: nil, avatar: child.avatar))
  }

  /// Creates a room in this space and opens it.
  public func createChannel(named name: String) async {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !isCreating else { return }
    isCreating = true
    defer { isCreating = false }
    errorMessage = nil
    do {
      let roomId = try await repository.createChannel(named: name, in: space.id)
      await load()
      onOpen(
        RoomSummary(
          id: roomId, name: name, lastMessageText: nil, lastMessageSender: nil, lastActivity: nil))
    } catch {
      errorMessage = "Could not create the channel."
    }
  }

  public func makeNewSubspace(onCreated: @escaping @MainActor () -> Void) -> NewSpaceViewModel? {
    guard canAddChannel else { return nil }
    return NewSpaceViewModel(parentId: space.id, repository: repository) { [weak self] _ in
      onCreated()
      Task { await self?.load() }
    }
  }

  /// Marks every room the user is in read: this space's and its sub-spaces', as the web's "Mark space as read".
  public func markAllRead() async {
    guard let markRead, !isMarkingRead else { return }
    isMarkingRead = true
    defer { isMarkingRead = false }
    var pending = [space.id]
    var seen = Set(pending)
    while let spaceId = pending.popLast() {
      let found =
        spaceId == space.id
        ? (children ?? []) : ((try? await repository.children(of: spaceId)) ?? [])
      for child in found where seen.insert(child.id).inserted {
        if child.isSpace {
          pending.append(child.id)
        } else if child.isJoined {
          await markRead(child.id)
        }
      }
    }
  }

  /// The page of a sub-space.
  public func subspace(_ child: SpaceChild) -> SpaceViewModel {
    SpaceViewModel(
      space: RoomSummary(
        id: child.id, name: child.name, lastMessageText: nil, lastMessageSender: nil,
        lastActivity: nil, avatar: child.avatar, isSpace: true),
      repository: repository, picture: picture, onOpen: onOpen, markRead: markRead)
  }
}

/// One space page is one value: the chat list pushes it with `navigationDestination(item:)`.
extension SpaceViewModel: Hashable {
  nonisolated public static func == (lhs: SpaceViewModel, rhs: SpaceViewModel) -> Bool {
    lhs === rhs
  }
  nonisolated public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// A space page: its picture and name, then its sub-spaces and rooms, each with its picture, description and size.
struct SpaceScreen: View {
  let viewModel: SpaceViewModel
  @State private var isNaming = false
  @State private var newName = ""
  @State private var newSubspace: NewSpaceViewModel?

  var body: some View {
    List {
      Section {
        VStack(spacing: 8) {
          // The web's page style: its cover above, the avatar over its lower edge, ringed in its colour.
          if let style = viewModel.pageStyle {
            PageCover(style: style, picture: viewModel.picture).padding(.bottom, -44)
          }
          TwakeAvatar(
            name: viewModel.space.name, size: 72, pictureID: viewModel.space.avatar?.source,
            load: viewModel.space.avatar.map { reference in
              { @Sendable [picture = viewModel.picture] in await picture(reference) }
            }
          )
          .pageAccentRing(viewModel.pageStyle, size: 72)
          Text(viewModel.space.name).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
          if let children = viewModel.children {
            Text(children.count == 1 ? "1 room" : "\(children.count) rooms")
              .font(.subheadline)
              .foregroundStyle(SysColors.textSecondary)
          }
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
      }
      if let children = viewModel.children {
        Section {
          ForEach(children) { child in
            if child.isSpace {
              NavigationLink {
                SpaceScreen(viewModel: viewModel.subspace(child))
              } label: {
                row(child)
              }
              .accessibilityIdentifier(A11yIdentifiers.space.child(child.name))
            } else {
              Button {
                Task { await viewModel.open(child) }
              } label: {
                row(child)
              }
              .foregroundStyle(SysColors.onSurface)
              .accessibilityIdentifier(A11yIdentifiers.space.child(child.name))
            }
          }
        }
        if children.isEmpty, viewModel.errorMessage == nil {
          Text("This space has no rooms yet.")
            .foregroundStyle(SysColors.textSecondary)
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
      } else {
        ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
      }
      if let message = viewModel.errorMessage {
        Text(message).foregroundStyle(SysColors.error)
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(viewModel.space.name)
    .navigationBarTitleDisplayMode(.inline)
    .alert("New channel", isPresented: $isNaming) {
      TextField("Name", text: $newName)
      Button("Cancel", role: .cancel) {}
      Button("Create") {
        let name = newName
        newName = ""
        Task { await viewModel.createChannel(named: name) }
      }
    } message: {
      Text("Members of \(viewModel.space.name) can find it in the space.")
    }
    .toolbar {
      if viewModel.canAddChannel {
        ToolbarItem(placement: .topBarTrailing) {
          Menu("Add", systemImage: "plus") {
            Button("New Channel", systemImage: "number") { isNaming = true }
            Button("New Sub-space", systemImage: "cube") {
              newSubspace = viewModel.makeNewSubspace { newSubspace = nil }
            }
            .accessibilityIdentifier(A11yIdentifiers.space.newSubspace)
          }
          .accessibilityIdentifier(A11yIdentifiers.space.add)
          .disabled(viewModel.isCreating)
        }
      }
      if viewModel.markRead != nil {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Mark All as Read", systemImage: "envelope.open") {
            Task { await viewModel.markAllRead() }
          }
          .disabled(viewModel.isMarkingRead || viewModel.children == nil)
          .symbolEffect(.bounce, value: viewModel.isMarkingRead)
        }
      }
    }
    .task { await viewModel.load() }
    .refreshable { await viewModel.load() }
    .sheet(item: $newSubspace) { model in NewSpaceScreen(viewModel: model) }
  }

  private func row(_ child: SpaceChild) -> some View {
    HStack(spacing: 12) {
      TwakeAvatar(
        name: child.name, size: 40, pictureID: child.avatar?.source,
        load: child.avatar.map { reference in
          { @Sendable [picture = viewModel.picture] in await picture(reference) }
        }
      )
      .pageAccentRing(viewModel.childStyles[child.id], size: 40)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          if child.isSpace {
            Image(systemName: "square.stack.3d.up").font(.caption).foregroundStyle(
              SysColors.textSecondary)
          }
          Text(child.name).font(.body.weight(.medium)).lineLimit(1)
        }
        Text(detail(child)).font(.footnote).foregroundStyle(SysColors.textSecondary).lineLimit(2)
      }
      Spacer(minLength: 8)
      if viewModel.joining.contains(child.id) {
        ProgressView()
      } else if !child.isJoined, child.isSpace {
        // Its own button: the row opens the sub-space to look inside, Join makes the user a member.
        Button("Join") { Task { await viewModel.join(subspace: child) } }
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(SysColors.primary)
          .buttonStyle(.borderless)
      } else if !child.isJoined {
        Text("Join")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(SysColors.primary)
      }
    }
  }

  private func detail(_ child: SpaceChild) -> String {
    let members = child.memberCount == 1 ? "1 member" : "\(child.memberCount) members"
    guard let topic = child.topic else { return members }
    return "\(topic) · \(members)"
  }
}
