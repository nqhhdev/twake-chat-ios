import DesignSystem
import Domain
import SwiftUI

@MainActor
@Observable
public final class DeleteAccountViewModel {
  public enum Route: Equatable {
    case commonSettings(URL)
    case matrix
  }

  public private(set) var route: Route?
  public private(set) var challenge: DeviceAuthChallenge?
  public private(set) var isDeleting = false
  public private(set) var errorMessage: String?

  @ObservationIgnored private let userId: String
  @ObservationIgnored private let capabilities: any ServerCapabilitiesRepository
  @ObservationIgnored private let repository: any AccountDeletionRepository
  @ObservationIgnored private let signOut: @MainActor () async -> Void

  public init(
    userId: String, capabilities: any ServerCapabilitiesRepository,
    repository: any AccountDeletionRepository, signOut: @escaping @MainActor () async -> Void
  ) {
    self.userId = userId
    self.capabilities = capabilities
    self.repository = repository
    self.signOut = signOut
  }

  public func load() async {
    let page = await capabilities.current().commonSettingsPage(for: userId)
    route = page.map(Route.commonSettings) ?? .matrix
  }

  public func delete() async {
    await deactivate(auth: nil)
  }

  public func confirm(password: String? = nil) async {
    guard let pending = challenge else { return }
    challenge = nil
    let auth: DeviceAuth =
      if let password { .password(password, session: pending.session) } else {
        .confirmedOnWeb(session: pending.session)
      }
    await deactivate(auth: auth)
  }

  public func cancel() { challenge = nil }

  private func deactivate(auth: DeviceAuth?) async {
    errorMessage = nil
    isDeleting = true
    defer { isDeleting = false }
    do {
      switch try await repository.deactivateAccount(auth: auth) {
      case .done:
        await signOut()
      case .needsConfirmation(let next):
        if auth != nil || (next.webURL == nil && !next.acceptsPassword) {
          errorMessage = "Could not confirm it is you. Please try again."
        } else {
          challenge = next
        }
      }
    } catch {
      errorMessage = "Could not delete your account."
    }
  }
}

struct DeleteAccountSection: View {
  let viewModel: DeleteAccountViewModel
  @State private var isConfirming = false
  @State private var password = ""
  @Environment(\.openURL) private var openURL

  var body: some View {
    Section {
      Button(role: .destructive) {
        switch viewModel.route {
        case .commonSettings(let url): openURL(url)
        case .matrix: isConfirming = true
        case nil: break
        }
      } label: {
        Label("Delete Account", systemImage: "person.crop.circle.badge.xmark")
          .foregroundStyle(SysColors.error)
      }
      .disabled(viewModel.route == nil || viewModel.isDeleting)
      .accessibilityIdentifier("settings.deleteAccount")
      if let message = viewModel.errorMessage {
        Text(message).foregroundStyle(SysColors.error)
      }
    } footer: {
      if case .commonSettings = viewModel.route {
        Text("Your account is managed on your organisation's settings page.")
      }
    }
    .task { await viewModel.load() }
    .confirmationDialog(
      "Delete your account?", isPresented: $isConfirming, titleVisibility: .visible
    ) {
      Button("Delete Account", role: .destructive) { Task { await viewModel.delete() } }
    } message: {
      Text(
        "Your account is closed for good: you leave every chat, sign out of every device and lose your encrypted messages. Nobody can use your Matrix ID again."
      )
    }
    .sheet(
      isPresented: Binding(
        get: { viewModel.challenge?.webURL != nil },
        set: { if !$0 { Task { await viewModel.confirm() } } })
    ) {
      if let url = viewModel.challenge?.webURL {
        SafariView(url: url).ignoresSafeArea()
      }
    }
    .alert(
      "Confirm it is you",
      isPresented: Binding(
        get: {
          viewModel.challenge.map { $0.webURL == nil && $0.acceptsPassword } ?? false
        },
        set: { if !$0 { password = "" } })
    ) {
      SecureField("Password", text: $password)
      Button("Cancel", role: .cancel) { viewModel.cancel() }
      Button("Delete Account", role: .destructive) {
        let typed = password
        password = ""
        Task { await viewModel.confirm(password: typed) }
      }
    } message: {
      Text("Enter your account password to delete your account.")
    }
  }
}
