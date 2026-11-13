import Authentication
import AuthenticationServices
import UIKit

/// `WebAuthenticator` on `ASWebAuthenticationSession`, as the Flutter app's `flutter_web_auth_2` opens its SSO pages:
/// the page runs in a system browser sheet and the session ends when the page calls back on `callbackScheme`.
@MainActor
final class SystemWebAuthenticator: NSObject, WebAuthenticator,
  ASWebAuthenticationPresentationContextProviding
{
  /// The running session; ASWebAuthenticationSession stops when nothing holds it.
  private var session: ASWebAuthenticationSession?

  func authenticate(url: URL, callbackScheme: String) async throws(WebAuthenticationError) -> URL {
    let result: Result<URL, WebAuthenticationError> = await withCheckedContinuation {
      continuation in
      let session = ASWebAuthenticationSession(
        url: url, callback: .customScheme(callbackScheme)
      ) { callbackURL, error in
        if let callbackURL {
          continuation.resume(returning: .success(callbackURL))
        } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
          continuation.resume(returning: .failure(.cancelled))
        } else {
          continuation.resume(returning: .failure(.failed))
        }
      }
      session.presentationContextProvider = self
      // The Flutter app keeps the browser's cookies so a Twake account already signed in is reused.
      session.prefersEphemeralWebBrowserSession = false
      self.session = session
      if !session.start() {
        continuation.resume(returning: .failure(.failed))
      }
    }
    session = nil
    return try result.get()
  }

  nonisolated func presentationAnchor(for session: ASWebAuthenticationSession)
    -> ASPresentationAnchor
  {
    MainActor.assumeIsolated {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
  }
}
