import DesignSystem
import Domain
import Observation
import SwiftUI

/// The chats the user left (Flutter `archive`). A chat opens read-only; it can be joined again or deleted for good, one
/// at a time or all at once, each deletion confirmed first as the Flutter app does.
@MainActor @Observable
public final class ArchivedChatsViewModel {
  /// `nil` until loaded.
  public private(set) var rooms: [RoomSummary]?
  public private(set) var errorMessage: String?
  public private(set) var working: Set<String> = []

  @ObservationIgnored private let repository: any ArchivedRoomsRepository

  public init(repository: any ArchivedRoomsRepository) {
    self.repository = repository
  }

  public func load() async {
    do {
      rooms = try await repository.archivedRooms()
    } catch {
      rooms = []
      errorMessage = localized("Could not load the archived chats.")
    }
  }

  /// Joins a left chat again; it goes back to the chat list. Returns whether it worked.
  @discardableResult
  public func rejoin(_ room: RoomSummary) async -> Bool {
    await act(
      on: room, failure: localized("Could not join \(room.name) again. It may need an invitation.")
    ) {
      [repository] in try await repository.rejoin(roomId: room.id)
    }
  }

  /// Deletes a left chat for good.
  @discardableResult
  public func delete(_ room: RoomSummary) async -> Bool {
    await act(on: room, failure: localized("Could not delete \(room.name). Please try again.")) {
      [repository] in try await repository.forget(roomId: room.id)
    }
  }

  /// Deletes every archived chat, as Flutter's "Clear archive"; one that fails stays in the list.
  public func deleteAll() async {
    for room in rooms ?? [] { await delete(room) }
  }

  private func act(
    on room: RoomSummary, failure: String, _ action: @escaping () async throws -> Void
  ) async -> Bool {
    guard !working.contains(room.id) else { return false }
    working.insert(room.id)
    defer { working.remove(room.id) }
    errorMessage = nil
    do {
      try await action()
      withAnimation { rooms?.removeAll { $0.id == room.id } }
      return true
    } catch {
      errorMessage = failure
      return false
    }
  }
}

/// The archive: the left chats as chat list rows, swipe or long press to rejoin or delete, and Delete All.
struct ArchivedChatsScreen: View {
  @State var viewModel: ArchivedChatsViewModel
  let list: ChatListViewModel
  let onSelect: (RoomSummary) -> Void
  @State private var deleting: RoomSummary?
  @State private var isConfirmingDeleteAll = false

  var body: some View {
    Group {
      if let rooms = viewModel.rooms {
        if rooms.isEmpty {
          ContentUnavailableView(
            localized("No archived chats"), systemImage: "archivebox",
            description: Text(localized("Chats you leave show here.")))
        } else {
          List {
            ForEach(rooms) { room in
              Button {
                onSelect(room)
              } label: {
                ChatListRow(room: room, viewModel: list)
              }
              .buttonStyle(.plain)
              .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
              .disabled(viewModel.working.contains(room.id))
              .swipeActions(edge: .trailing) {
                Button(localized("Delete"), systemImage: "trash", role: .destructive) {
                  deleting = room
                }
              }
              .swipeActions(edge: .leading) {
                Button(localized("Rejoin"), systemImage: "arrow.uturn.left") {
                  Task { await viewModel.rejoin(room) }
                }
                .tint(SysColors.primary)
              }
              .contextMenu {
                Button(localized("Rejoin"), systemImage: "arrow.uturn.left") {
                  Task { await viewModel.rejoin(room) }
                }
                Button(localized("Delete"), systemImage: "trash", role: .destructive) {
                  deleting = room
                }
              }
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
    .navigationTitle(localized("Archived"))
    .toolbar {
      if viewModel.rooms?.isEmpty == false {
        Button(localized("Delete All"), role: .destructive) { isConfirmingDeleteAll = true }
      }
    }
    .task { await viewModel.load() }
    .refreshable { await viewModel.load() }
    .confirmationDialog(
      localized("Delete \(deleting?.name ?? localized("this chat"))?"),
      isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
      titleVisibility: .visible
    ) {
      Button(localized("Delete"), role: .destructive) {
        if let room = deleting { Task { await viewModel.delete(room) } }
      }
    } message: {
      Text(localized("Its messages will no longer be kept on this account. This cannot be undone."))
    }
    .confirmationDialog(
      localized("Delete all archived chats?"), isPresented: $isConfirmingDeleteAll,
      titleVisibility: .visible
    ) {
      Button(localized("Delete All"), role: .destructive) { Task { await viewModel.deleteAll() } }
    } message: {
      Text(localized("This cannot be undone."))
    }
  }
}
