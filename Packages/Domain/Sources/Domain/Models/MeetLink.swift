import Foundation

/// The link of a Meet video call, in the form the Twake clients post it in a room (#92): the account's Meet base URL
/// (from the homeserver's well-known), then one slug of three, four and three lowercase letters, such as
/// `https://meet.example.org/abc-defg-hij`. The app shows a call card only for a link of that form on its own Meet
/// server, so a message cannot dress any link up as a call.
public enum MeetLink {
  /// The text of a call message before its link, as the Flutter app posts it (`videoCallStartedTitle`).
  public static let startedTitle = "Has started a video call"

  /// A Meet base URL a slug can be appended to: `https` with a host, no query or fragment, without the trailing slash;
  /// `nil` otherwise.
  public static func base(_ url: URL) -> URL? {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.scheme?.lowercased() == "https", components.host?.isEmpty == false,
      components.query == nil, components.fragment == nil
    else { return nil }
    while components.path.hasSuffix("/") { components.path.removeLast() }
    return components.url
  }

  /// `abc-defg-hij`: three, four and three lowercase ASCII letters.
  public static func isSlug(_ text: some StringProtocol) -> Bool {
    let parts = text.split(separator: "-", omittingEmptySubsequences: false)
    return parts.map(\.count) == [3, 4, 3]
      && parts.allSatisfy { $0.unicodeScalars.allSatisfy { ("a"..."z").contains($0) } }
  }

  /// A new random slug; the system generator is cryptographically secure.
  public static func randomSlug() -> String {
    var generator = SystemRandomNumberGenerator()
    return randomSlug(using: &generator)
  }

  public static func randomSlug(using generator: inout some RandomNumberGenerator) -> String {
    let letters = Array("abcdefghijklmnopqrstuvwxyz")
    func word(_ length: Int) -> String {
      String((0..<length).map { _ in letters.randomElement(using: &generator)! })
    }
    return "\(word(3))-\(word(4))-\(word(3))"
  }

  /// The link of a call with `slug` on `base`.
  public static func link(slug: String, base: URL) -> URL {
    base.appending(path: slug)
  }

  /// The slug of `url` when it is exactly one slug under `base`, on the same scheme, host and port, with no query or
  /// fragment; `nil` otherwise.
  public static func slug(of url: URL, base: URL) -> String? {
    guard let room = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let home = URLComponents(url: base, resolvingAgainstBaseURL: false),
      room.scheme?.lowercased() == home.scheme?.lowercased(),
      room.host?.lowercased() == home.host?.lowercased(), room.port == home.port,
      room.query == nil, room.fragment == nil
    else { return nil }
    let baseSegments = home.path.split(separator: "/")
    let segments = room.path.split(separator: "/")
    guard segments.count == baseSegments.count + 1, segments.starts(with: baseSegments),
      let slug = segments.last, isSlug(slug)
    else { return nil }
    return String(slug)
  }

  /// The call link a message carries (`call_url`) when it is a call on `base`, `nil` otherwise.
  public static func callLink(_ text: String, base: URL) -> URL? {
    guard let url = URL(string: text), slug(of: url, base: base) != nil else { return nil }
    return url
  }
}
