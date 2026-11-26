import DesignSystem
import Domain
import SwiftUI

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
