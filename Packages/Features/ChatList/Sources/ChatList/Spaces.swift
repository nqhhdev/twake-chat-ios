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

  public init(
    space: RoomSummary, repository: any SpacesRepository,
    picture: @escaping @Sendable (MediaReference) async -> Data?,
    onOpen: @escaping @MainActor (RoomSummary) -> Void
  ) {
    self.space = space
    self.repository = repository
    self.picture = picture
    self.onOpen = onOpen
  }

  public func load() async {
    errorMessage = nil
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
          memberCount: child.memberCount, isJoined: true, isSpace: false, via: child.via)
      }
    }
    onOpen(
      RoomSummary(
        id: roomId, name: child.name, lastMessageText: nil, lastMessageSender: nil,
        lastActivity: nil, avatar: child.avatar))
  }

  /// The page of a sub-space.
  public func subspace(_ child: SpaceChild) -> SpaceViewModel {
    SpaceViewModel(
      space: RoomSummary(
        id: child.id, name: child.name, lastMessageText: nil, lastMessageSender: nil,
        lastActivity: nil, avatar: child.avatar, isSpace: true),
      repository: repository, picture: picture, onOpen: onOpen)
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

  var body: some View {
    List {
      Section {
        VStack(spacing: 8) {
          TwakeAvatar(
            name: viewModel.space.name, size: 72, pictureID: viewModel.space.avatar?.source,
            load: viewModel.space.avatar.map { reference in
              { @Sendable [picture = viewModel.picture] in await picture(reference) }
            })
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
            } else {
              Button {
                Task { await viewModel.open(child) }
              } label: {
                row(child)
              }
              .foregroundStyle(SysColors.onSurface)
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
    .task { await viewModel.load() }
    .refreshable { await viewModel.load() }
  }

  private func row(_ child: SpaceChild) -> some View {
    HStack(spacing: 12) {
      TwakeAvatar(
        name: child.name, size: 40, pictureID: child.avatar?.source,
        load: child.avatar.map { reference in
          { @Sendable [picture = viewModel.picture] in await picture(reference) }
        })
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
      } else if !child.isJoined, !child.isSpace {
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
