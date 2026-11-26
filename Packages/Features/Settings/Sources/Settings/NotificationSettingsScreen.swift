import DesignSystem
import Domain
import SwiftUI

struct NotificationSettingsScreen: View {
  let viewModel: SettingsViewModel

  var body: some View {
    List {
      Section {
        Toggle(
          isOn: Binding(
            get: { viewModel.doNotDisturb },
            set: { on in Task { await viewModel.setDoNotDisturb(on) } })
        ) {
          Label("Do Not Disturb", systemImage: "moon.fill")
        }
        .tint(.indigo)
      } footer: {
        Text("No notifications on any of your devices until you turn it off.")
      }
      modePicker("Direct Chats", selection: viewModel.directMode, isDirect: true)
      modePicker("Group chats", selection: viewModel.groupMode, isDirect: false)
      if let message = viewModel.errorMessage {
        Section { Text(message).foregroundStyle(SysColors.error) }
      }
    }
    .twakeTitle("Notifications")
  }

  private func modePicker(_ title: String, selection: NotificationMode, isDirect: Bool) -> some View
  {
    Section(title) {
      ForEach(NotificationMode.allCases, id: \.self) { mode in
        Button {
          Task { await viewModel.setNotificationMode(mode, isDirect: isDirect) }
        } label: {
          HStack {
            Text(SettingsViewModel.title(of: mode)).foregroundStyle(SysColors.onSurface)
            Spacer()
            if mode == selection {
              Image(systemName: "checkmark").foregroundStyle(SysColors.primary).transition(.scale)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selection)
    .sensoryFeedback(.selection, trigger: selection)
  }
}
