import Foundation

/// Opens a sign-in page in a web authentication session and returns the URL it called back on. The app implements it
/// with `ASWebAuthenticationSession`; the feature imports only what ADR 0005 allows.
public protocol WebAuthenticator: Sendable {
  @MainActor func authenticate(url: URL, callbackScheme: String)
    async throws(WebAuthenticationError) -> URL
}

public enum WebAuthenticationError: Error, Sendable, Equatable {
  /// The user closed the page.
  case cancelled
  /// The session could not start or ended without a callback.
  case failed
}
