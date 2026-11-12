// Debug only (ADR 0019): a Release build cannot sign in, so it never has a saved session to keep.
#if DEBUG
  import SwiftUI

  /// Shown when the saved session could not be restored at launch. The session is kept; `retry` asks the root to
  /// restore it again, and `logOut` is the way out when the error does not pass (it signs out and shows the sign-in
  /// form). `errorMessage` is shown when Log out failed. It holds no logic.
  public struct RestoreFailedScreen: View {
    let errorMessage: String?
    let retry: () -> Void
    let logOut: () -> Void

    public init(errorMessage: String?, retry: @escaping () -> Void, logOut: @escaping () -> Void) {
      self.errorMessage = errorMessage
      self.retry = retry
      self.logOut = logOut
    }

    public var body: some View {
      VStack(spacing: 16) {
        Text("Can't open your session")
          .font(.headline)
        Text("You are still signed in. Check the connection and try again.")
          .font(.subheadline)
          .multilineTextAlignment(.center)
        Button("Try again", action: retry)
        Button("Log out", role: .destructive, action: logOut)
        if let errorMessage {
          Text(errorMessage).foregroundStyle(.red)
        }
      }
      .padding()
    }
  }
#endif
