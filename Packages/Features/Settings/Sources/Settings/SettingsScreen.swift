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
        .accessibilityHint("Changes your picture and display name")
        Button {
          statusDraft = viewModel.statusMessage ?? ""
          isEditingStatus = true
        } label: {
          Label {
            Text(viewModel.statusMessage ?? "Set a status")
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
            Text("Your personal QR").foregroundStyle(SysColors.onSurface)
          } icon: {
            Image(systemName: "qrcode").foregroundStyle(SysColors.primary)
          }
        }
        .accessibilityIdentifier(A11yIdentifiers.settings.personalQR)
      }
      Section {
        if viewModel.hasChatPage {
          pageRow(.chat, title: "Chat", icon: "bubble.left.and.bubble.right", detail: nil)
        }
        pageRow(.security, title: "Privacy & Security", icon: "lock", detail: recoveryBadge)
        pageRow(.notifications, title: "Notifications", icon: "bell", detail: nil)
        pageRow(.storage, title: "Data and Storage", icon: "internaldrive", detail: nil)
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
        .accessibilityIdentifier(A11yIdentifiers.settings.logout)
        if let message = viewModel.errorMessage {
          Text(message).foregroundStyle(SysColors.error)
        }
      }
      if let help = viewModel.help {
        HelpSection(viewModel: help)
      }
      if let deleteAccount = viewModel.deleteAccount {
        DeleteAccountSection(viewModel: deleteAccount)
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
    .task { await viewModel.help?.load() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await viewModel.refreshDisplayName() } }
    }
    .sheet(isPresented: $isRenaming) { EditProfileSheet(viewModel: viewModel) }
    .alert("Status", isPresented: $isEditingStatus) {
      TextField("What are you up to?", text: $statusDraft)
      Button("Cancel", role: .cancel) {}
      if viewModel.statusMessage != nil {
        Button("Clear", role: .destructive) { Task { await viewModel.setStatusMessage("") } }
      }
      Button("Save") {
        let text = statusDraft
        Task { await viewModel.setStatusMessage(text) }
      }
    } message: {
      Text("People see it on your profile.")
    }
    .confirmationDialog(
      "Are you sure you want to log out?", isPresented: $isConfirmingLogout,
      titleVisibility: .visible
    ) {
      Button("Logout", role: .destructive) { Task { await viewModel.logOut() } }
        .accessibilityIdentifier(A11yIdentifiers.settings.confirmLogout)
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
  @State private var isConfirmingReset = false
  @State private var resetPassword = ""

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
      if viewModel.didResetIdentity {
        Section {
          Label(
            "Your identity was reset. Set up the chat backup again.",
            systemImage: "checkmark.shield"
          )
          .foregroundStyle(SysColors.success)
        }
        .transition(.scale.combined(with: .opacity))
      }
      if let message = viewModel.errorMessage {
        Section { Text(message).foregroundStyle(SysColors.error) }
      }
      if viewModel.isWorking {
        Section { ProgressView().frame(maxWidth: .infinity) }
      }
      Section {
        Button("Reset identity", role: .destructive) { isConfirmingReset = true }
          .disabled(viewModel.isWorking)
      } footer: {
        Text(
          "Only if you lost every device and your recovery key. Your verified devices and people must verify you again, and older encrypted messages stay locked."
        )
      }
    }
    .twakeTitle("Privacy & Security")
    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.didResetIdentity)
    .confirmationDialog(
      "Reset your identity?", isPresented: $isConfirmingReset, titleVisibility: .visible
    ) {
      Button("Reset", role: .destructive) { Task { await viewModel.startIdentityReset() } }
    } message: {
      Text("This cannot be undone.")
    }
    .alert(
      "Confirm with your password",
      isPresented: Binding(
        get: { viewModel.identityReset == .password },
        set: { if !$0 { resetPassword = "" } })
    ) {
      SecureField("Password", text: $resetPassword)
      Button("Cancel", role: .cancel) { Task { await viewModel.cancelIdentityReset() } }
      Button("Reset", role: .destructive) {
        let typed = resetPassword
        resetPassword = ""
        Task { await viewModel.finishIdentityReset(password: typed) }
      }
    }
    .sheet(
      isPresented: Binding(
        get: { if case .webApproval = viewModel.identityReset { true } else { false } },
        set: { if !$0 { Task { await viewModel.finishIdentityReset() } } })
    ) {
      if case .webApproval(let url) = viewModel.identityReset {
        SafariView(url: url).ignoresSafeArea()
      }
    }
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

/// The new recovery key, shown once, with Copy and Share. The app also shows it after sign-in when ToM did not keep the
/// key the unlock made (ADR 0024).
public struct RecoveryKeySheet: View {
  let key: String
  let done: () -> Void

  public init(key: String, done: @escaping () -> Void) {
    self.key = key
    self.done = done
  }

  public var body: some View {
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

/// Data and Storage (Flutter `settings_data_and_storage`): how much the cached messages and media take, and a button
/// that empties them; they load again from the server. Keys and the session are never cleared.
struct StorageSettingsScreen: View {
  let viewModel: SettingsViewModel
  @State private var isConfirming = false
  @State private var isAddingEmail = false
  @State private var newEmail = ""
  @State private var isAddingPhone = false
  @State private var newPhone = ""
  @State private var removing: LinkedAddress?

  var body: some View {
    List {
      if let addresses = viewModel.linkedAddresses,
        !addresses.isEmpty || viewModel.canChangeLinkedAddresses
      {
        Section {
          ForEach(addresses) { address in
            Label(address.address, systemImage: address.kind == .email ? "envelope" : "phone")
              .textSelection(.enabled)
              .swipeActions {
                if viewModel.canChangeLinkedAddresses {
                  Button("Remove", role: .destructive) { removing = address }
                }
              }
          }
          if viewModel.canChangeLinkedAddresses {
            Button("Add e-mail", systemImage: "plus") { isAddingEmail = true }
              .disabled(viewModel.isChangingAddresses)
            Button("Add phone number", systemImage: "plus") { isAddingPhone = true }
              .disabled(viewModel.isChangingAddresses)
          }
        } header: {
          Text("E-mails and phones")
        } footer: {
          Text("People who have these in their contacts can find you.")
        }
      }
      if let visibility = viewModel.contactsVisibility {
        Section {
          Picker(
            "Who sees them",
            selection: Binding(
              get: { visibility },
              set: { new in Task { await viewModel.setContactsVisibility(new) } })
          ) {
            Text("Nobody").tag(ContactsVisibility.nobody)
            Text("My contacts").tag(ContactsVisibility.contacts)
            Text("Everyone").tag(ContactsVisibility.everyone)
          }
          .pickerStyle(.inline)
          .labelsHidden()
        } header: {
          Text("Who sees my e-mail and phone")
        }
        .transition(.opacity)
      }
      Section {
        LabeledContent("Cache") {
          if let size = viewModel.cacheSize {
            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
              .contentTransition(.numericText(value: Double(size)))
          } else {
            ProgressView()
          }
        }
        Button("Clear Cache", role: .destructive) { isConfirming = true }
          .disabled(viewModel.isClearingCache)
      } footer: {
        Text(
          "Messages and media load again from the server. Your keys and session stay on this device."
        )
      }
      if let message = viewModel.errorMessage {
        Section { Text(message).foregroundStyle(SysColors.error) }
      }
    }
    .twakeTitle("Data and Storage")
    .overlay { if viewModel.isClearingCache { ProgressView().controlSize(.large) } }
    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.cacheSize)
    .animation(.easeInOut(duration: 0.25), value: viewModel.contactsVisibility)
    .sensoryFeedback(.selection, trigger: viewModel.contactsVisibility)
    .task {
      async let size: Void = viewModel.loadCacheSize()
      async let addresses: Void = viewModel.loadLinkedAddresses()
      async let visibility: Void = viewModel.loadContactsVisibility()
      _ = await (size, addresses, visibility)
    }
    .confirmationDialog("Clear the cache?", isPresented: $isConfirming, titleVisibility: .visible) {
      Button("Clear Cache", role: .destructive) { Task { await viewModel.clearCache() } }
    }
    .overlay { if viewModel.isChangingAddresses { ProgressView().controlSize(.large) } }
    .modifier(LinkedAddressDialogs(viewModel: viewModel))
    .alert("Add an e-mail", isPresented: $isAddingEmail) {
      TextField("E-mail", text: $newEmail)
        .keyboardType(.emailAddress)
        .textContentType(.emailAddress)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      Button("Cancel", role: .cancel) { newEmail = "" }
      Button("Send link") {
        let typed = newEmail
        newEmail = ""
        Task { await viewModel.addEmail(typed) }
      }
    } message: {
      Text("We will send a link to this address to confirm it is yours.")
    }
    .alert("Add a phone number", isPresented: $isAddingPhone) {
      TextField("+33 6 12 34 56 78", text: $newPhone)
        .keyboardType(.phonePad)
        .textContentType(.telephoneNumber)
      Button("Cancel", role: .cancel) { newPhone = "" }
      Button("Send code") {
        let typed = newPhone
        newPhone = ""
        Task { await viewModel.addPhone(typed) }
      }
    } message: {
      Text("We will send a code to this number by text message to confirm it is yours.")
    }
    .confirmationDialog(
      "Remove \(removing?.address ?? "")?",
      isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
      titleVisibility: .visible
    ) {
      Button("Remove", role: .destructive) {
        if let address = removing { Task { await viewModel.removeLinkedAddress(address) } }
      }
    } message: {
      Text("People will no longer find you by it.")
    }
  }
}

/// The steps after the link is sent: open it and come back, then confirm it is you on the web page or with the
/// password when the server asks (User-Interactive Authentication), as signing devices out does.
private struct LinkedAddressDialogs: ViewModifier {
  let viewModel: SettingsViewModel
  @State private var password = ""
  @State private var code = ""

  func body(content: Content) -> some View {
    content
      .alert(
        "Enter the code",
        isPresented: Binding(
          get: {
            viewModel.pendingPhone != nil && viewModel.linkChallenge == nil
              && !viewModel.isChangingAddresses
          },
          set: { if !$0 { code = "" } })
      ) {
        TextField("Code", text: $code)
          .keyboardType(.numberPad)
          .textContentType(.oneTimeCode)
        Button("Cancel", role: .cancel) { viewModel.cancelLinking() }
        Button("Confirm") {
          let typed = code
          code = ""
          Task { await viewModel.submitPhoneCode(typed) }
        }
      } message: {
        let phone = viewModel.pendingPhone?.phone ?? ""
        Text(
          viewModel.phoneCodeRejected
            ? "This code is not right. Check the text message sent to \(phone) and try again."
            : "We sent a code to \(phone). Enter it to confirm the number is yours.")
      }
      .alert(
        "Check your inbox",
        isPresented: Binding(
          get: {
            viewModel.pendingEmail != nil && viewModel.linkChallenge == nil
              && !viewModel.isChangingAddresses
          },
          set: { _ in })
      ) {
        Button("Cancel", role: .cancel) { viewModel.cancelLinking() }
        Button("I opened the link") { Task { await viewModel.finishLinkingEmail() } }
      } message: {
        let email = viewModel.pendingEmail?.email ?? ""
        Text(
          viewModel.emailNotConfirmed
            ? "The link was not opened yet. Open the link sent to \(email), then try again."
            : "We sent a link to \(email). Open it, then come back here.")
      }
      .sheet(
        isPresented: Binding(
          get: { viewModel.linkChallenge?.webURL != nil },
          set: { if !$0 { Task { await viewModel.confirmLinking() } } })
      ) {
        if let url = viewModel.linkChallenge?.webURL {
          SafariView(url: url).ignoresSafeArea()
        }
      }
      .alert(
        "Confirm it is you",
        isPresented: Binding(
          get: {
            viewModel.linkChallenge.map { $0.webURL == nil && $0.acceptsPassword } ?? false
          },
          set: { if !$0 { password = "" } })
      ) {
        SecureField("Password", text: $password)
        Button("Cancel", role: .cancel) { viewModel.cancelLinking() }
        Button("Add") {
          let typed = password
          password = ""
          Task { await viewModel.confirmLinking(password: typed) }
        }
      } message: {
        Text(
          viewModel.pendingPhone == nil
            ? "Enter your account password to add the e-mail."
            : "Enter your account password to add the phone number.")
      }
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
