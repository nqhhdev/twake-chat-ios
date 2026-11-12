// Debug only (ADR 0019): a Release build of the app must not contain the password sign-in flow.
#if DEBUG
  import SwiftUI

  /// The password sign-in form. It shows the view model's state and forwards the sign-in tap; it holds no logic.
  public struct PasswordLoginScreen: View {
    @Bindable var viewModel: PasswordLoginViewModel

    public init(viewModel: PasswordLoginViewModel) {
      self.viewModel = viewModel
    }

    public var body: some View {
      Form {
        Section {
          TextField("Homeserver", text: $viewModel.homeserver)
            .textContentType(.URL)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        Section {
          TextField("Username", text: $viewModel.username)
            .textContentType(.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          if let usernameError = viewModel.usernameError {
            Text(usernameError).foregroundStyle(.red)
          }
          SecureField("Password", text: $viewModel.password)
            .textContentType(.password)
          if let passwordError = viewModel.passwordError {
            Text(passwordError).foregroundStyle(.red)
          }
        }
        if let errorMessage = viewModel.errorMessage {
          Section {
            Text(errorMessage).foregroundStyle(.red)
          }
        }
        Section {
          Button {
            Task { await viewModel.signIn() }
          } label: {
            if viewModel.isLoading {
              ProgressView()
            } else {
              Text("Sign in")
            }
          }
          .disabled(viewModel.isLoading)
        }
      }
      .disabled(viewModel.isLoading)
    }
  }
#endif
