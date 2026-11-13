import Domain
import Foundation
import Testing

/// The way in follows the Flutter homeserver picker (homeserver_picker.dart:146-243).
struct HomeserverLoginOptionsTests {
  private let homeserver = URL(string: "https://matrix.example.org")!
  private let twake = HomeserverLoginOptions.IdentityProvider(id: "oidc-twake", name: "Twake SSO")

  private func options(
    password: Bool, sso: Bool, providers: [HomeserverLoginOptions.IdentityProvider],
    registration: Bool
  ) -> HomeserverLoginOptions {
    HomeserverLoginOptions(
      homeserver: homeserver, supportsPassword: password, supportsSSO: sso,
      identityProviders: providers,
      registrationSupported: registration)
  }

  @Test func aServerWithoutSSOUsesThePasswordForm() {
    #expect(
      options(password: true, sso: false, providers: [], registration: true).signInRoute
        == .password)
  }

  @Test func oneProviderAndNoRegistrationGoesStraightToSSO() {
    #expect(
      options(password: true, sso: true, providers: [twake], registration: false).signInRoute
        == .sso(twake))
  }

  @Test func registrationShowsTheConnectPage() {
    #expect(
      options(password: false, sso: true, providers: [twake], registration: true).signInRoute
        == .connect)
  }

  @Test func severalProvidersShowTheConnectPage() {
    let other = HomeserverLoginOptions.IdentityProvider(id: "gitlab", name: "GitLab")
    #expect(
      options(password: false, sso: true, providers: [twake, other], registration: false)
        .signInRoute == .connect)
  }
}
