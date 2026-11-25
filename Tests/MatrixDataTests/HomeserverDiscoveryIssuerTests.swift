import Foundation
import Testing

@testable import MatrixData

/// The `m.authentication` issuer the Flutter app keeps as `authUrl` for its SSO sign-out.
struct HomeserverDiscoveryIssuerTests {
  private func issuer(_ json: String) -> URL? {
    HomeserverDiscovery.authenticationIssuer(wellKnown: Data(json.utf8))
  }

  /// The staging `.well-known/matrix/client`, shortened.
  @Test func readsTheIssuer() {
    #expect(
      issuer(
        #"{"m.homeserver":{"base_url":"https://matrix.stg.lin-saas.com/"},"#
          + #""m.authentication":{"issuer":"https://sign-up.stg.lin-saas.com/"}}"#)
        == URL(string: "https://sign-up.stg.lin-saas.com/"))
  }

  @Test(arguments: [
    #"{"m.homeserver":{"base_url":"https://matrix.example.org/"}}"#,
    #"{"m.authentication":{}}"#,
    #"{"m.authentication":{"issuer":"not a url"}}"#,
    #"{"m.authentication":{"issuer":"twake.chat://redirect"}}"#,
    "not json",
  ])
  func noUsableIssuerIsNil(json: String) {
    #expect(issuer(json) == nil)
  }
}
