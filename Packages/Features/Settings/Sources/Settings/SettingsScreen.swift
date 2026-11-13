import DesignSystem
import Domain
import SwiftUI

/// The Settings tab: the profile card, then the Flutter sections with their icons, then Logout with its confirmation.
/// It shows the view model's state and forwards taps; it holds no logic.
/// The pages Settings opens.
public enum SettingsPage: Hashable, CaseIterable, Sendable {
  case chat, security, notifications, about
}

/// One Settings page on its own, for the column beside the list on a wide screen.
public struct SettingsPageView: View {
  let page: SettingsPage
  let viewModel: SettingsViewModel

  public init(page: SettingsPage, viewModel: SettingsViewModel) {
    self.page = page
    self.viewModel = viewModel
  }

  public var body: some View {
    switch page {
    case .chat: ChatSettingsScreen(viewModel: viewModel)
    case .security: SecurityScreen(viewModel: viewModel)
    case .notifications: NotificationSettingsScreen(viewModel: viewModel)
    case .about: AboutScreen()
    }
  }
}

/// Settings as the iOS Settings app lays it out: the large title, the profile card (a tap renames), then the pages and
/// Logout in inset groups. On a phone a page is pushed; on a wide screen the app shows the chosen page beside the list
/// (`selection`), as iPad Settings does.
public struct SettingsScreen: View {
  let viewModel: SettingsViewModel
  let selection: Binding<SettingsPage?>?
  @State private var isConfirmingLogout = false
  @State private var isRenaming = false

  public init(viewModel: SettingsViewModel, selection: Binding<SettingsPage?>? = nil) {
    self.viewModel = viewModel
    self.selection = selection
  }

  /// A row that pushes its page on a phone, or selects it for the column beside the list on a wide screen.
  @ViewBuilder private func pageRow(
    _ page: SettingsPage, title: String, icon: String, detail: String?
  )
    -> some View
  {
    if let selection {
      Button {
        selection.wrappedValue = page
      } label: {
        SettingsRow(title: title, icon: icon, detail: detail)
      }
      .listRowBackground(
        Rectangle().fill(
          selection.wrappedValue == page ? SysColors.secondaryContainer : SysColors.onPrimary))
    } else {
      NavigationLink(value: page) {
        SettingsRow(title: title, icon: icon, detail: detail)
      }
    }
  }

  public var body: some View {
    List {
      Section {
        HStack(spacing: 16) {
          TwakeAvatar(
            name: viewModel.displayName, size: 64, pictureID: viewModel.avatar?.source,
            load: viewModel.avatar.map { reference in
              { @Sendable [viewModel] in await viewModel.picture(reference) }
            })
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
        // The profile row opens the profile editor (picture and name), as the Flutter profile page does.
        .contentShape(Rectangle())
        .onTapGesture { isRenaming = true }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Changes your picture and display name")
      }
      Section {
        if viewModel.hasChatPage {
          pageRow(.chat, title: "Chat", icon: "bubble.left.and.bubble.right", detail: nil)
        }
        pageRow(.security, title: "Privacy & Security", icon: "lock", detail: recoveryBadge)
        pageRow(.notifications, title: "Notifications", icon: "bell", detail: nil)
        pageRow(.about, title: "About", icon: "info.circle", detail: nil)
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
    .listStyle(.insetGrouped)
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.large)
    .navigationDestination(for: SettingsPage.self) { page in
      SettingsPageView(page: page, viewModel: viewModel)
    }
    .animation(.default, value: viewModel.displayName)
    .task { await viewModel.load() }
    .sheet(isPresented: $isRenaming) { EditProfileSheet(viewModel: viewModel) }
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
      Text(title).textStyle(TextStyles.bodyLarge).foregroundStyle(SysColors.onSurface).lineLimit(1)
      Spacer()
      if let detail {
        // A red badge, as iOS Settings marks a page that needs attention; the words are for VoiceOver.
        Image(systemName: "exclamationmark.circle.fill")
          .font(.system(size: 20))
          .foregroundStyle(SysColors.error)
          .accessibilityLabel(detail)
      }
    }
  }
}

/// App Lock (Flutter `setAppLockAction`): a switch named after the device's Face ID, Touch ID or passcode. Changing it
/// asks the owner first, so the switch moves only when they pass.
struct AppLockSection: View {
  let lock: any AppLockSettings

  var body: some View {
    let method = lock.unlockMethod
    Section {
      Toggle(
        "Require \(method?.name ?? "Passcode")",
        isOn: Binding(
          get: { lock.isEnabled },
          set: { enabled in Task { await lock.setEnabled(enabled) } })
      )
      .disabled(method == nil)
    } header: {
      Text("App Lock")
    } footer: {
      if let method {
        Text("Twake Chat asks for \(method.name) when it opens and each time you come back to it.")
      } else {
        Text("Set a passcode on this device to lock Twake Chat.")
      }
    }
  }
}

/// Chat (Flutter `SettingsChatView`): which room events chats show. Both kinds are hidden by default; a change applies
/// to the open chat at once.
struct ChatSettingsScreen: View {
  @Bindable var viewModel: SettingsViewModel

  var body: some View {
    List {
      Section {
        Toggle(
          "Hide unimportant room events", isOn: $viewModel.chatDisplay.hidesUnimportantEvents)
      } footer: {
        Text("Changes to a chat's encryption, description, join rules, history or permissions.")
      }
      Section {
        Toggle("Hide unknown events", isOn: $viewModel.chatDisplay.hidesUnknownEvents)
      } footer: {
        Text("Events this app cannot show, listed by their type.")
      }
    }
    .listStyle(.insetGrouped)
    .twakeTitle("Chat")
  }
}

/// Privacy & Security: the chat backup. Incomplete asks for the recovery key; disabled offers to set it up and shows the
/// new key once.
struct SecurityScreen: View {
  let viewModel: SettingsViewModel
  @State private var key = ""
  @State private var isVerifying = false

  var body: some View {
    List {
      if let verification = viewModel.verification {
        Section {
          // A plain row: a Label inside LabeledContent made the row stretch to fill the page.
          HStack {
            Text("This device")
            Spacer()
            HStack(spacing: 6) {
              Image(
                systemName: verification.state == .verified
                  ? "checkmark.seal.fill" : "exclamationmark.shield")
              Text(verification.state == .verified ? "Verified" : "Not verified")
            }
            .foregroundStyle(verification.state == .verified ? SysColors.success : SysColors.error)
          }
          .accessibilityElement(children: .combine)
          if verification.state != .verified {
            Button("Verify with another device") {
              isVerifying = true
              Task { await verification.start() }
            }
          }
        } footer: {
          Text(
            "A verified device is trusted by your other devices and can read your older encrypted messages."
          )
        }
      }
      if let appLock = viewModel.appLock {
        AppLockSection(lock: appLock)
      }
      Section {
        if let devices = viewModel.devices {
          NavigationLink {
            DevicesScreen(viewModel: devices)
          } label: {
            Label("Devices", systemImage: "laptopcomputer.and.iphone")
          }
        }
        NavigationLink {
          BlockedUsersScreen(viewModel: viewModel)
        } label: {
          Label("Blocked people", systemImage: "hand.raised")
        }
      }
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
    .task { await viewModel.verification?.refreshState() }
    .sheet(isPresented: $isVerifying) {
      if let verification = viewModel.verification {
        VerificationSheet(viewModel: verification)
      }
    }
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

/// The people the user blocked; swipe or tap Unblock to see their messages and invitations again.
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
