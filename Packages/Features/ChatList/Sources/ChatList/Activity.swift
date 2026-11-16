import DesignSystem
import Domain
import SwiftUI

extension ChatListViewModel {
  /// The rooms with something unread, the most recent first: the activity's inbox (web D57).
  public var inbox: [RoomSummary] {
    joinedRooms.filter { $0.isUnread && !$0.isSpace }
  }

  /// The rooms where someone mentioned the user and it is not read yet.
  public var mentioned: [RoomSummary] {
    joinedRooms.filter { $0.mentionCount > 0 }
  }

  /// Something waits in the activity's inbox: the bell shows its badge, also without a mention.
  public var hasActivity: Bool { !inbox.isEmpty }

  /// The mentions not read yet, read out with the bell.
  public var mentionTotal: Int {
    joinedRooms.reduce(0) { $0 + $1.mentionCount }
  }
}

/// Activity (web D57, D318): what needs the user, opened from the bell of the chat list. Mentions first, then the inbox
/// of every room with something unread, each with a button that marks it read; the saved messages last.
struct ActivityScreen: View {
  let viewModel: ChatListViewModel
  let onSelect: (RoomSummary) -> Void

  var body: some View {
    List {
      let mentioned = viewModel.mentioned
      if !mentioned.isEmpty {
        Section("Mentions") {
          ForEach(mentioned) { room in row(room, badge: "@\(room.mentionCount)") }
        }
      }
      Section("Inbox") {
        let inbox = viewModel.inbox
        if inbox.isEmpty {
          Label("You are all caught up.", systemImage: "checkmark.circle")
            .foregroundStyle(SysColors.textSecondary)
            .transition(.opacity)
        }
        ForEach(inbox) { room in
          row(room, badge: room.unreadCount > 0 ? "\(room.unreadCount)" : "•")
        }
      }
      if let saved = viewModel.saved {
        Section {
          NavigationLink {
            SavedMessagesScreen(repository: saved)
          } label: {
            Label("Saved messages", systemImage: "bookmark")
          }
        }
      }
    }
    .navigationTitle("Activity")
    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.inbox)
  }

  private func row(_ room: RoomSummary, badge: String) -> some View {
    HStack(spacing: 12) {
      Button {
        onSelect(room)
      } label: {
        VStack(alignment: .leading, spacing: 3) {
          Text(room.name).font(.body.weight(.semibold)).lineLimit(1)
          Text(ChatListViewModel.preview(of: room) ?? " ")
            .font(.subheadline)
            .foregroundStyle(SysColors.textSecondary)
            .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      Text(badge)
        .font(.caption.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(SysColors.primary, in: Capsule())
      Button {
        Task { await viewModel.setUnread(false, room: room) }
      } label: {
        Image(systemName: "envelope.open")
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("Mark \(room.name) as read")
    }
    .transition(.move(edge: .trailing).combined(with: .opacity))
  }
}
