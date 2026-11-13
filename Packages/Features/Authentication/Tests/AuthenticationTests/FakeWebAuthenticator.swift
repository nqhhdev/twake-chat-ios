import Authentication
import Foundation

/// A hand-written `WebAuthenticator` (ADR 0010): records each page it is asked to open and answers with the scripted
/// callback or error.
@MainActor
final class FakeWebAuthenticator: WebAuthenticator {
  struct Call: Equatable {
    let url: URL
    let callbackScheme: String
  }

  var result: Result<URL, WebAuthenticationError> = .failure(.cancelled)
  private(set) var calls: [Call] = []

  func authenticate(url: URL, callbackScheme: String) async throws(WebAuthenticationError) -> URL {
    calls.append(Call(url: url, callbackScheme: callbackScheme))
    return try result.get()
  }
}
