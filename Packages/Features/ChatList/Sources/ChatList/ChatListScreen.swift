import DesignSystem
import Domain
import SwiftUI

/// The joined rooms, as the Flutter chat list shows them: avatar, name, time of the last message and its preview, and
/// a Log out button. A tap opens the room through `onSelect`; the open room is highlighted when the list sits beside
/// it. The app puts it in a navigation stack. It holds no logic.
public struct ChatListScreen: View {
  let viewModel: ChatListViewModel
  let selectedRoomId: String?
  let onSelect: (RoomSummary) -> Void

  public init(
    viewModel: ChatListViewModel, selectedRoomId: String? = nil,
    onSelect: @escaping (RoomSummary) -> Void = { _ in }
  ) {
    self.viewModel = viewModel
    self.selectedRoomId = selectedRoomId
    self.onSelect = onSelect
  }

  public var body: some View {
    content
      .background(SysColors.background)
      .navigationTitle("Chats")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Log out", role: .destructive) {
            Task { await viewModel.logOut() }
          }
          .disabled(viewModel.isLoggingOut)
        }
      }
      .safeAreaInset(edge: .bottom) {
        if let message = viewModel.logOutErrorMessage {
          Text(message).foregroundStyle(SysColors.error).padding()
        }
      }
      .task { await viewModel.start() }
  }

  @ViewBuilder private var content: some View {
    switch viewModel.state {
    case .loading:
      ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    case .empty:
      ContentUnavailableView("No rooms yet", systemImage: "bubble.left.and.bubble.right")
    case .failed(let message):
      ContentUnavailableView(message, systemImage: "exclamationmark.triangle")
    case .loaded(let rooms):
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(rooms) { room in
            Button {
              onSelect(room)
            } label: {
              ChatListRow(room: room, isSelected: room.id == selectedRoomId)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }
}

/// One room: avatar, name and time on the first line, the last message below, 72 pt tall
/// (`chat_list_item_style.dart`).
struct ChatListRow: View {
  let room: RoomSummary
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 8) {
      TwakeAvatar(name: room.name, size: 56)
      VStack(alignment: .leading, spacing: 2) {
        HStack {
          Text(room.name)
            .textStyle(TextStyles.titleMedium)
            .foregroundStyle(SysColors.onSurface)
            .lineLimit(1)
          Spacer(minLength: 4)
          if let date = room.lastActivity {
            Text(ChatListViewModel.timeText(date))
              .textStyle(TextStyles.labelSmall)
              .foregroundStyle(SysColors.textSecondary)
          }
        }
        if let preview = ChatListViewModel.preview(of: room) {
          Text(preview)
            .textStyle(TextStyles.bodyMedium)
            .foregroundStyle(SysColors.textSecondary)
            .lineLimit(1)
        }
      }
    }
    .padding(.horizontal, 16)
    .frame(minHeight: 72)
    .background(isSelected ? SysColors.secondaryContainer : ColorToken(0x0000_0000))
    .contentShape(Rectangle())
  }
}
