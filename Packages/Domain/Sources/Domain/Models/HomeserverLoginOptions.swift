import Foundation

/// What a homeserver offers for signing in, as the Flutter app's homeserver picker reads it
/// (twake-on-matrix lib/pages/homeserver_picker/homeserver_picker.dart, `checkHomeserverAction`).
public struct HomeserverLoginOptions: Sendable, Equatable {
  /// One SSO identity provider the homeserver lists in its `m.login.sso` flow.
  public struct IdentityProvider: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
      self.id = id
      self.name = name
    }
  }

  /// The homeserver's base URL, after discovery.
  public let homeserver: URL
  public let supportsPassword: Bool
  public let supportsSSO: Bool
  public let identityProviders: [IdentityProvider]
  /// Whether the server lets a new account register (it answers a registration probe with an interactive flow).
  public let registrationSupported: Bool

  public init(
    homeserver: URL, supportsPassword: Bool, supportsSSO: Bool,
    identityProviders: [IdentityProvider],
    registrationSupported: Bool
  ) {
    self.homeserver = homeserver
    self.supportsPassword = supportsPassword
    self.supportsSSO = supportsSSO
    self.identityProviders = identityProviders
    self.registrationSupported = registrationSupported
  }

  /// The way in the Flutter app picks for this server: SSO straight away when the server has SSO, no registration
  /// and exactly one identity provider; the password form when it has no SSO; otherwise the connect page.
  public var signInRoute: SignInRoute {
    if !supportsSSO { return .password }
    if !registrationSupported, identityProviders.count == 1 { return .sso(identityProviders[0]) }
    if !registrationSupported, supportsPassword, identityProviders.isEmpty { return .password }
    return .connect
  }

  public enum SignInRoute: Sendable, Equatable {
    case password
    case sso(IdentityProvider)
    case connect
  }
}
