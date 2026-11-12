// Debug only (ADR 0019): a Release build of the app must not contain the password sign-in flow.
#if DEBUG
  import SwiftUI

  /// Shows the signed-in user id and a Log out button. It holds no logic.
  public struct SignedInScreen: View {
    let viewModel: SignedInViewModel

    public init(viewModel: SignedInViewModel) {
      self.viewModel = viewModel
    }

    public var body: some View {
      Form {
        Section("Signed in as") {
          Text(viewModel.userId)
        }
        Section {
          Button("Log out", role: .destructive) {
            Task { await viewModel.logOut() }
          }
          .disabled(viewModel.isLoggingOut)
        } footer: {
          if let errorMessage = viewModel.errorMessage {
            Text(errorMessage).foregroundStyle(.red)
          }
        }
      }
    }
  }
#endif
