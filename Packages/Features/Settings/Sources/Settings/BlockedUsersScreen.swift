import DesignSystem
import Domain
import SwiftUI

struct BlockedUsersScreen: View {
  let viewModel: SettingsViewModel
  @State private var confirming: BlockedUser?

  var body: some View {
    Group {
      if let users = viewModel.blockedUsers {
        if users.isEmpty {
          ContentUnavailableView(
            "No one blocked", systemImage: "hand.raised",
            description: Text("People you block from a chat show here."))
        } else {
          List {
            ForEach(users) { user in
              HStack(spacing: 12) {
                TwakeAvatar(name: user.name, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                  Text(user.name).lineLimit(1)
                  if user.displayName != nil {
                    Text(user.id).font(.footnote).foregroundStyle(SysColors.textSecondary)
                      .lineLimit(1)
                  }
                }
                Spacer()
                Button("Unblock") { confirming = user }
                  .buttonStyle(.bordered)
              }
              .swipeActions {
                Button("Unblock") { confirming = user }.tint(SysColors.primary)
              }
            }
            if let message = viewModel.errorMessage {
              Text(message).foregroundStyle(SysColors.error)
            }
          }
          .refreshable { await viewModel.loadBlockedUsers() }
        }
      } else {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .navigationTitle("Blocked people")
    .task { await viewModel.loadBlockedUsers() }
    .confirmationDialog(
      confirming.map { "Unblock \($0.name)?" } ?? "",
      isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
      titleVisibility: .visible
    ) {
      Button("Unblock") {
        if let user = confirming { Task { await viewModel.unblock(user) } }
      }
    } message: {
      Text("Their messages and invitations will show again.")
    }
  }
}
