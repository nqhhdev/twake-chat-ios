import DesignSystem
import Domain
import SwiftUI

/// The Settings tab: the profile card, then the Flutter sections with their icons, then Logout with its confirmation.
/// It shows the view model's state and forwards taps; it holds no logic.
/// The pages Settings opens.
public enum SettingsPage: Hashable, CaseIterable, Sendable {
  case chat, security, notifications, storage, about
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
    case .storage: StorageSettingsScreen(viewModel: viewModel)
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
  @State private var isEditingStatus = false
  @State private var statusDraft = ""
  @Environment(\.scenePhase) private var scenePhase

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
              .accessibilityIdentifier(A11yIdentifiers.settings.displayName)
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
        .accessibilityHint(localized("Changes your picture and display name"))
        Button {
          statusDraft = viewModel.statusMessage ?? ""
          isEditingStatus = true
        } label: {
          Label {
            Text(viewModel.statusMessage ?? localized("Set a status"))
              .foregroundStyle(
                viewModel.statusMessage == nil ? SysColors.textSecondary : SysColors.onSurface
              )
              .contentTransition(.opacity)
          } icon: {
            Image(systemName: "quote.bubble").foregroundStyle(SysColors.primary)
          }
        }
        .animation(.easeInOut, value: viewModel.statusMessage)
        NavigationLink {
          PersonalQRScreen(settings: viewModel)
        } label: {
          Label {
            Text(localized("Your personal QR")).foregroundStyle(SysColors.onSurface)
          } icon: {
            Image(systemName: "qrcode").foregroundStyle(SysColors.primary)
          }
        }
        .accessibilityIdentifier(A11yIdentifiers.settings.personalQR)
      }
      Section {
        if viewModel.hasChatPage {
          pageRow(
            .chat, title: localized("Chat"), icon: "bubble.left.and.bubble.right", detail: nil)
        }
        pageRow(
          .security, title: localized("Privacy & Security"), icon: "lock", detail: recoveryBadge)
        pageRow(.notifications, title: localized("Notifications"), icon: "bell", detail: nil)
        pageRow(.storage, title: localized("Data and Storage"), icon: "internaldrive", detail: nil)
        pageRow(.about, title: localized("About"), icon: "info.circle", detail: nil)
      }
      Section {
        Button(role: .destructive) {
          isConfirmingLogout = true
        } label: {
          Label(localized("Logout"), systemImage: "rectangle.portrait.and.arrow.right")
            .foregroundStyle(SysColors.error)
        }
        .disabled(viewModel.isLoggingOut)
        .accessibilityIdentifier(A11yIdentifiers.settings.logout)
        if let message = viewModel.errorMessage {
          Text(message).foregroundStyle(SysColors.error)
        }
      }
      if let appGrid = viewModel.appGrid {
        AppGridRow(viewModel: appGrid)
      }
      if let help = viewModel.help {
        HelpSection(viewModel: help)
      }
      if let usageAnalytics = viewModel.usageAnalytics {
        UsageAnalyticsSection(viewModel: usageAnalytics)
      }
      if let deleteAccount = viewModel.deleteAccount {
        DeleteAccountSection(viewModel: deleteAccount)
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(localized("Settings"))
    .navigationBarTitleDisplayMode(.large)
    .navigationDestination(for: SettingsPage.self) { page in
      SettingsPageView(page: page, viewModel: viewModel)
    }
    .animation(.default, value: viewModel.displayName)
    .task { await viewModel.load() }
    .task { await viewModel.help?.load() }
    .task { await viewModel.usageAnalytics?.load() }
    .task { await viewModel.appGrid?.load() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await viewModel.refreshDisplayName() } }
    }
    .sheet(isPresented: $isRenaming) { EditProfileSheet(viewModel: viewModel) }
    .alert(localized("Status"), isPresented: $isEditingStatus) {
      TextField(localized("What are you up to?"), text: $statusDraft)
      Button(localized("Cancel"), role: .cancel) {}
      if viewModel.statusMessage != nil {
        Button(localized("Clear"), role: .destructive) {
          Task { await viewModel.setStatusMessage("") }
        }
      }
      Button(localized("Save")) {
        let text = statusDraft
        Task { await viewModel.setStatusMessage(text) }
      }
    } message: {
      Text(localized("People see it on your profile."))
    }
    .confirmationDialog(
      localized("Are you sure you want to log out?"), isPresented: $isConfirmingLogout,
      titleVisibility: .visible
    ) {
      Button(localized("Logout"), role: .destructive) { Task { await viewModel.logOut() } }
        .accessibilityIdentifier(A11yIdentifiers.settings.confirmLogout)
    }
  }

  /// A dot on Privacy & Security while older messages cannot be read yet.
  private var recoveryBadge: String? {
    viewModel.recoveryStatus == .incomplete ? localized("Action needed") : nil
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
        localized("Require \(method?.name ?? localized("Passcode"))"),
        isOn: Binding(
          get: { lock.isEnabled },
          set: { enabled in Task { await lock.setEnabled(enabled) } })
      )
      .disabled(method == nil)
    } header: {
      Text(localized("App Lock"))
    } footer: {
      if let method {
        Text(
          localized(
            "Twake Chat asks for \(method.name) when it opens and each time you come back to it."))
      } else {
        Text(localized("Set a passcode on this device to lock Twake Chat."))
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
          localized("Hide unimportant room events"),
          isOn: $viewModel.chatDisplay.hidesUnimportantEvents)
      } footer: {
        Text(
          localized(
            "Changes to a chat's encryption, description, join rules, history or permissions."))
      }
      Section {
        Toggle(localized("Hide unknown events"), isOn: $viewModel.chatDisplay.hidesUnknownEvents)
      } footer: {
        Text(localized("Events this app cannot show, listed by their type."))
      }
    }
    .listStyle(.insetGrouped)
    .twakeTitle(localized("Chat"))
  }
}
