import DesignSystem
import Domain
import SwiftUI

/// The Settings tab: the profile card, then the Flutter sections with their icons, then Logout with its confirmation.
/// It shows the view model's state and forwards taps; it holds no logic.
public struct SettingsScreen: View {
  let viewModel: SettingsViewModel
  @State private var isConfirmingLogout = false

  public init(viewModel: SettingsViewModel) {
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
              .contentTransition(.opacity)
            Text(viewModel.userId)
              .textStyle(TextStyles.bodyMedium)
              .foregroundStyle(SysColors.textSecondary)
              .lineLimit(1)
          }
        }
        .padding(.vertical, 8)
      }
      Section {
        NavigationLink {
          SecurityScreen(viewModel: viewModel)
        } label: {
          SettingsRow(title: "Privacy & Security", icon: "lock", detail: recoveryBadge)
        }
        NavigationLink {
          NotificationSettingsScreen(viewModel: viewModel)
        } label: {
          SettingsRow(title: "Notifications", icon: "bell", detail: nil)
        }
        NavigationLink {
          AboutScreen()
        } label: {
          SettingsRow(title: "About", icon: "info.circle", detail: nil)
        }
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
    .animation(.default, value: viewModel.displayName)
    .task { await viewModel.load() }
    .confirmationDialog(
      "Are you sure you want to log out?", isPresented: $isConfirmingLogout,
      titleVisibility: .visible
    ) {
      Button("Logout", role: .destructive) { Task { await viewModel.logOut() } }
    }
  }

  /// A dot on Privacy & Security while older messages cannot be read yet.
  private var recoveryBadge: String? {
    viewModel.recoveryStatus == .incomplete ? "Action needed" : nil
  }
}

struct SettingsRow: View {
  let title: String
  let icon: String
  let detail: String?

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 18))
        .foregroundStyle(SysColors.primary)
        .frame(width: 28)
      Text(title).textStyle(TextStyles.bodyLarge).foregroundStyle(SysColors.onSurface)
      Spacer()
      if let detail {
        Text(detail)
          .textStyle(TextStyles.labelMedium)
          .foregroundStyle(SysColors.onError)
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(SysColors.error, in: Capsule())
      }
    }
  }
}

/// Privacy & Security: the chat backup. Incomplete asks for the recovery key; disabled offers to set it up and shows the
/// new key once.
struct SecurityScreen: View {
  let viewModel: SettingsViewModel
  @State private var key = ""

  var body: some View {
    List {
      Section {
        LabeledContent("Chat backup", value: statusText)
      } footer: {
        Text(
          "Your messages are encrypted. The recovery key unlocks older messages on a new device.")
      }
      switch viewModel.recoveryStatus {
      case .incomplete:
        Section("Enter recovery key") {
          SecureField("Recovery key", text: $key)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          Button("Unlock old messages") { Task { await viewModel.recover(with: key) } }
            .disabled(key.isEmpty || viewModel.isWorking)
        }
      case .disabled:
        Section {
          Button("Set up chat backup") { Task { await viewModel.enableRecovery() } }
            .disabled(viewModel.isWorking)
        }
      case .enabled, .unknown:
        EmptyView()
      }
      if viewModel.didRecover {
        Section {
          Label("Old messages are unlocked.", systemImage: "checkmark.seal").foregroundStyle(
            SysColors.success)
        }
        .transition(.scale.combined(with: .opacity))
      }
      if let message = viewModel.errorMessage {
        Section { Text(message).foregroundStyle(SysColors.error) }
      }
      if viewModel.isWorking {
        Section { ProgressView().frame(maxWidth: .infinity) }
      }
    }
    .twakeTitle("Privacy & Security")
    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.didRecover)
    .sheet(
      isPresented: Binding(
        get: { viewModel.newRecoveryKey != nil },
        set: { if !$0 { viewModel.dismissNewRecoveryKey() } })
    ) {
      if let key = viewModel.newRecoveryKey {
        RecoveryKeySheet(key: key) { viewModel.dismissNewRecoveryKey() }
      }
    }
  }

  private var statusText: String {
    switch viewModel.recoveryStatus {
    case .enabled: "On"
    case .disabled: "Off"
    case .incomplete: "Needs your recovery key"
    case .unknown: "Checking…"
    }
  }
}

/// The new recovery key, shown once, with Copy and Share.
struct RecoveryKeySheet: View {
  let key: String
  let done: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "key.horizontal").font(.system(size: 40)).foregroundStyle(SysColors.primary)
      Text("Recovery key").textStyle(TextStyles.titleLarge)
      Text(
        "Store securely on this device or in your password manager. You need it to read old messages on a new device."
      )
      .textStyle(TextStyles.bodyMedium)
      .foregroundStyle(SysColors.textSecondary)
      .multilineTextAlignment(.center)
      Text(key)
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(SysColors.surface, in: .rect(cornerRadius: 12))
      HStack {
        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = key }
        ShareLink(item: key)
      }
      .buttonStyle(.bordered)
      Button("Done", action: done).buttonStyle(.twakePrimary)
    }
    .padding(24)
    .presentationDetents([.medium, .large])
    .interactiveDismissDisabled()
  }
}

/// Notifications: what direct and group chats notify by default.
struct NotificationSettingsScreen: View {
  let viewModel: SettingsViewModel

  var body: some View {
    List {
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

struct AboutScreen: View {
  var body: some View {
    List {
      Section {
        VStack(spacing: 8) {
          TwakeLogo(TwakeLogo.welcomeResource, width: 180, height: 118)
          Text("Version \(SettingsViewModel.appVersion)")
            .textStyle(TextStyles.bodyMedium)
            .foregroundStyle(SysColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
      }
      Section {
        Link("Privacy Policy", destination: URL(string: "https://twake.app/policy")!)
        Link(
          "Source code (AGPL-3.0)",
          destination: URL(string: "https://github.com/linagora/twake-on-matrix")!)
      }
    }
    .twakeTitle("About")
  }
}
