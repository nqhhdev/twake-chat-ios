import Foundation

/// The sign-in settings of the Flutter app's `config.json` and `AppConfig`, read by the app from its build
/// configuration: staging values in Debug, Twake SaaS values in Release.
public struct SignInConfiguration: Sendable, Equatable {
  /// The Twake sign-up site that both Sign in and Create Twake ID open (`registration_url`).
  public let registrationURL: URL?
  /// The homeserver that a Twake ID signs in to (`twake_workplace_homeserver`).
  public let workplaceHomeserver: URL?
  /// Prefills the company-server field (`homeserver`).
  public let defaultHomeserver: URL?
  /// The privacy policy the welcome footer links to (`AppConfig.privacyUrl`).
  public let privacyURL: URL

  /// The URL scheme the web sessions call back on, registered in the app's Info.plist.
  public static let callbackScheme = "twake.chat"
  /// Where the registration site sends the user back with a `loginToken` (`AppConfig.appOpenUrlScheme` redirect).
  public static let registrationRedirectURL = URL(string: "twake.chat://redirect")!
  /// Where a homeserver's SSO sends the user back with a `loginToken` (`connect_page_mixin.dart` `_getRedirectUrl`).
  public static let ssoRedirectURL = URL(string: "twake.chat://login")!

  public init(
    registrationURL: URL?, workplaceHomeserver: URL?, defaultHomeserver: URL?, privacyURL: URL
  ) {
    self.registrationURL = registrationURL
    self.workplaceHomeserver = workplaceHomeserver
    self.defaultHomeserver = defaultHomeserver
    self.privacyURL = privacyURL
  }

  /// Whether the Twake ID buttons show: the Flutter welcome shows them only on the SaaS platform, which has both URLs.
  public var offersTwakeID: Bool { registrationURL != nil && workplaceHomeserver != nil }

  /// The page that ends the SSO session of `issuer`: `<issuer>?logout=1` (connect_page_mixin.dart `_getLogoutUrl`).
  public static func ssoLogoutURL(issuer: URL) -> URL? {
    guard var components = URLComponents(url: issuer, resolvingAgainstBaseURL: false) else {
      return nil
    }
    components.queryItems =
      (components.queryItems ?? []) + [URLQueryItem(name: "logout", value: "1")]
    return components.url
  }

  /// The registration-site URL for Sign in (`post_login_redirect_url`) or Create Twake ID
  /// (`post_registered_redirect_url`), with `app=chat` (twake_welcome.dart:62-139).
  public func registrationSiteURL(signUp: Bool) -> URL? {
    guard let registrationURL,
      var components = URLComponents(url: registrationURL, resolvingAgainstBaseURL: false)
    else { return nil }
    let redirectName = signUp ? "post_registered_redirect_url" : "post_login_redirect_url"
    components.queryItems =
      (components.queryItems ?? []) + [
        URLQueryItem(name: redirectName, value: Self.registrationRedirectURL.absoluteString),
        URLQueryItem(name: "app", value: "chat"),
      ]
    return components.url
  }
}
