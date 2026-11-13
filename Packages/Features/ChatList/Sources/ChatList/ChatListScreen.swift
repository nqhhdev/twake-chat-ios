import Domain
import SwiftUI

/// The joined rooms, each with its name and last message, and a Log out button. It shows the view model's state and
/// forwards taps; it holds no logic.
public struct ChatListScreen: View {
  let viewModel: ChatListViewModel

  public init(viewModel: ChatListViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    NavigationStack {
      content
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
            Text(message).foregroundStyle(.red).padding()
          }
        }
    }
    .task { await viewModel.start() }
  }

  @ViewBuilder private var content: some View {
    switch viewModel.state {
    case .loading:
      ProgressView()
    case .empty:
      ContentUnavailableView("No rooms yet", systemImage: "bubble.left.and.bubble.right")
    case .failed(let message):
      ContentUnavailableView(message, systemImage: "exclamationmark.triangle")
    case .loaded(let rooms):
      List(rooms) { room in
        ChatListRow(name: room.name, preview: ChatListViewModel.preview(of: room))
      }
      .listStyle(.plain)
    }
  }
}

/// One room: its name and, below it, the last message.
struct ChatListRow: View {
  let name: String
  let preview: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(name).font(.headline).lineLimit(1)
      if let preview {
        Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
      }
    }
  }
}
