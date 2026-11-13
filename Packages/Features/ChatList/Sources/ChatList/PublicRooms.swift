import DesignSystem
import Domain
import Observation
import SwiftUI

/// The homeserver's public groups (Flutter `public_rooms`): browse them, search by name from 2 letters, then join one
/// that is open or ask to join one that takes requests. Joining opens the chat.
@MainActor @Observable
public final class PublicRoomsViewModel {
  /// The shortest search the server is asked, as Flutter's `minSearchLength`.
  static let minimumSearchLength = 2
  static let debounce: Duration = .milliseconds(300)

  public var query = "" {
    didSet { if query != oldValue { queryChanged() } }
  }
  /// `nil` until the first page arrives.
  public private(set) var rooms: [PublicRoom]?
  public private(set) var reachedEnd = false
  public private(set) var isLoadingMore = false
  public private(set) var errorMessage: String?
  /// Rooms being joined or asked for.
  public private(set) var working: Set<String> = []
  /// Rooms the user asked to join in this session.
  public private(set) var requested: Set<String> = []

  @ObservationIgnored private let repository: any PublicRoomsRepository
  @ObservationIgnored private let onJoined: @MainActor (RoomSummary) -> Void
  @ObservationIgnored private var following: Task<Void, Never>?

  public init(
    repository: any PublicRoomsRepository, onJoined: @escaping @MainActor (RoomSummary) -> Void
  ) {
    self.repository = repository
    self.onJoined = onJoined
  }

  /// Browses the directory; the screen calls it once.
  public func start() {
    guard following == nil else { return }
    follow(nil)
  }

  public func stop() {
    following?.cancel()
    following = nil
  }

  private func queryChanged() {
    let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard term.isEmpty || term.count >= Self.minimumSearchLength else { return }
    following?.cancel()
    following = Task { [weak self] in
      try? await Task.sleep(for: Self.debounce)
      guard !Task.isCancelled else { return }
      await self?.run(term.isEmpty ? nil : term)
    }
  }

  private func follow(_ term: String?) {
    following = Task { [weak self] in await self?.run(term) }
  }

  private func run(_ term: String?) async {
    errorMessage = nil
    rooms = nil
    reachedEnd = false
    let stream: AsyncStream<[PublicRoom]>
    do {
      stream = try await repository.search(term)
    } catch {
      rooms = []
      reachedEnd = true
      errorMessage = "Could not load the public groups."
      return
    }
    for await page in stream {
      guard !Task.isCancelled else { return }
      withAnimation(.easeInOut(duration: 0.2)) { rooms = page }
    }
  }

  /// The next page, when the last row shows.
  public func loadMore() async {
    guard !isLoadingMore, !reachedEnd, rooms != nil else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      reachedEnd = try await repository.loadMore()
    } catch {
      reachedEnd = true
    }
  }

  /// Joins an open group and opens it; asks to join one that takes requests.
  public func open(_ room: PublicRoom) async {
    guard !working.contains(room.id), !requested.contains(room.id) else { return }
    working.insert(room.id)
    defer { working.remove(room.id) }
    errorMessage = nil
    switch room.access {
    case .open:
      do {
        let roomId = try await repository.join(roomId: room.id)
        onJoined(
          RoomSummary(
            id: roomId, name: room.name, lastMessageText: nil, lastMessageSender: nil,
            lastActivity: nil, avatar: room.avatar))
      } catch {
        errorMessage = "Could not join \(room.name). Please try again."
      }
    case .request:
      do {
        try await repository.requestToJoin(roomId: room.id)
        requested.insert(room.id)
      } catch {
        errorMessage = "Could not ask to join \(room.name). Please try again."
      }
    case .inviteOnly:
      errorMessage = "\(room.name) needs an invitation."
    }
  }
}

/// The public groups: the system search field, the groups as rows with their picture, name, description and size, and
/// Join, Request or "Invite only" on the trailing side.
struct PublicRoomsScreen: View {
  @State var viewModel: PublicRoomsViewModel
  let list: ChatListViewModel

  var body: some View {
    Group {
      if let rooms = viewModel.rooms {
        if rooms.isEmpty, viewModel.reachedEnd || viewModel.errorMessage != nil {
          ContentUnavailableView {
            Label("No public groups", systemImage: "person.3")
          } description: {
            Text(viewModel.errorMessage ?? "Try another name.")
          }
        } else {
          List {
            ForEach(rooms) { room in
              row(room)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .onAppear {
                  if room.id == rooms.last?.id { Task { await viewModel.loadMore() } }
                }
            }
            if viewModel.isLoadingMore {
              ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            }
            if let message = viewModel.errorMessage {
              Text(message).foregroundStyle(SysColors.error)
            }
          }
          .listStyle(.plain)
        }
      } else {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .navigationTitle("Public Groups")
    .searchable(text: $viewModel.query, prompt: "Search groups")
    .onAppear { viewModel.start() }
    .onDisappear { viewModel.stop() }
  }

  private func row(_ room: PublicRoom) -> some View {
    HStack(alignment: .top, spacing: 12) {
      TwakeAvatar(
        name: room.name, size: 48, pictureID: room.avatar?.source,
        load: room.avatar.map { reference in
          { @Sendable [list] in await list.picture(reference) }
        })
      VStack(alignment: .leading, spacing: 3) {
        Text(room.name).font(.headline).lineLimit(1)
        if let topic = room.topic {
          Text(topic).font(.subheadline).foregroundStyle(SysColors.textSecondary).lineLimit(2)
        }
        Text(room.memberCount == 1 ? "1 member" : "\(room.memberCount) members")
          .font(.caption)
          .foregroundStyle(SysColors.textSecondary)
      }
      Spacer(minLength: 8)
      action(for: room).padding(.top, 4)
    }
  }

  @ViewBuilder private func action(for room: PublicRoom) -> some View {
    if viewModel.working.contains(room.id) {
      ProgressView()
    } else if viewModel.requested.contains(room.id) {
      Text("Requested").font(.subheadline).foregroundStyle(SysColors.textSecondary)
    } else {
      switch room.access {
      case .open:
        Button("Join") { Task { await viewModel.open(room) } }
          .buttonStyle(.borderedProminent)
          .buttonBorderShape(.capsule)
          .controlSize(.small)
      case .request:
        Button("Request") { Task { await viewModel.open(room) } }
          .buttonStyle(.bordered)
          .buttonBorderShape(.capsule)
          .controlSize(.small)
      case .inviteOnly:
        Label("Invite only", systemImage: "lock")
          .font(.caption)
          .foregroundStyle(SysColors.textSecondary)
      }
    }
  }
}
