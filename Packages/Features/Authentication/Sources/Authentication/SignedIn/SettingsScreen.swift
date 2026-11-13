import DesignSystem
import SwiftUI

/// The Settings tab, as the Flutter `settings` page starts: the user's avatar, name and Matrix id, then Logout, which
/// asks first ("Are you sure you want to log out?"). The other Flutter settings (chat, privacy, notifications,
/// language, devices, storage, help, about, delete account) are not built yet, so they are not listed.
public struct SettingsScreen: View {
  let viewModel: SignedInViewModel
  @State private var isConfirmingLogout = false

  public init(viewModel: SignedInViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    List {
      Section {
        HStack(spacing: 16) {
          TwakeAvatar(name: viewModel.displayName, size: 64)
          VStack(alignment: .leading, spacing: 2) {
            Text(viewModel.displayName)
              .textStyle(TextStyles.titleLarge)
              .foregroundStyle(SysColors.onSurface)
              .lineLimit(1)
            Text(viewModel.userId)
              .textStyle(TextStyles.bodyMedium)
              .foregroundStyle(SysColors.textSecondary)
              .lineLimit(1)
          }
        }
        .padding(.vertical, 8)
      }
      Section {
        Button(role: .destructive) {
          isConfirmingLogout = true
        } label: {
          Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
            .foregroundStyle(SysColors.error)
        }
        .disabled(viewModel.isLoggingOut)
        if let message = viewModel.errorMessage {
          Text(message).foregroundStyle(SysColors.error)
        }
      }
    }
    .scrollContentBackground(.hidden)
    .background(SysColors.background)
    .twakeTitle("Settings")
    .confirmationDialog(
      "Are you sure you want to log out?", isPresented: $isConfirmingLogout,
      titleVisibility: .visible
    ) {
      Button("Logout", role: .destructive) { Task { await viewModel.logOut() } }
    }
  }
}
