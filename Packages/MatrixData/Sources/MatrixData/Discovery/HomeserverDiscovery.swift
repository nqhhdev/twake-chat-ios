import Domain
import Foundation

/// Reads how a homeserver lets users sign in, over plain HTTP, as the Flutter homeserver picker does
/// (twake-on-matrix lib/pages/homeserver_picker/homeserver_picker.dart:146-243): `.well-known` discovery, the login
/// flows and their SSO identity providers, and a registration probe. The pinned SDK lists no identity providers, so
/// this does not go through it.
public struct HomeserverDiscovery: Sendable {
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  /// What the user typed, as the Flutter app cleans it: trimmed, lower-cased, spaces turned into dashes, and
  /// `https://` added when there is no scheme. `nil` when nothing usable is left.
  public static func normalisedURL(from server: String) -> URL? {
    let cleaned = server.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      .replacingOccurrences(of: " ", with: "-")
    guard !cleaned.isEmpty else { return nil }
    let withScheme = cleaned.contains("://") ? cleaned : "https://\(cleaned)"
    guard let url = URL(string: withScheme), let scheme = url.scheme,
      ["https", "http"].contains(scheme),
      let host = url.host(), !host.isEmpty
    else { return nil }
    return url
  }

  public func loginOptions(server: String) async throws(AuthenticationError)
    -> HomeserverLoginOptions
  {
    guard let typed = Self.normalisedURL(from: server) else { throw .invalidHomeserverURL }
    let homeserver = await wellKnownHomeserver(for: typed) ?? typed
    let flows = try await loginFlows(homeserver: homeserver)
    let registration = await registrationSupported(homeserver: homeserver)
    let sso = flows.first { $0.type == "m.login.sso" }
    return HomeserverLoginOptions(
      homeserver: homeserver,
      supportsPassword: flows.contains { $0.type == "m.login.password" },
      supportsSSO: sso != nil,
      identityProviders: (sso?.identityProviders ?? []).map { .init(id: $0.id, name: $0.name) },
      registrationSupported: registration)
  }

  /// The status code and the body of `request`, or `nil` when it got no HTTP response.
  private func fetch(_ request: URLRequest) async -> (Int, Data)? {
    guard let result = try? await session.data(for: request),
      let response = result.1 as? HTTPURLResponse
    else { return nil }
    return (response.statusCode, result.0)
  }

  /// `m.homeserver.base_url` of the server's `.well-known/matrix/client`, or `nil` when it has none.
  private func wellKnownHomeserver(for url: URL) async -> URL? {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return nil
    }
    components.path = "/.well-known/matrix/client"
    components.query = nil
    guard let wellKnownURL = components.url,
      case (let status, let data)? = await fetch(URLRequest(url: wellKnownURL)), status == 200,
      let wellKnown = try? JSONDecoder().decode(WellKnown.self, from: data),
      let base = URL(string: wellKnown.homeserver.baseURL), base.host() != nil
    else { return nil }
    return base
  }

  private func loginFlows(homeserver: URL) async throws(AuthenticationError) -> [LoginFlows.Flow] {
    let url = homeserver.appending(path: "_matrix/client/v3/login")
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(from: url)
    } catch {
      throw (error as? URLError)?.code == .cannotFindHost
        ? .invalidHomeserverURL : .serverUnreachable
    }
    guard (response as? HTTPURLResponse)?.statusCode == 200,
      let flows = try? JSONDecoder().decode(LoginFlows.self, from: data)
    else { throw .invalidHomeserverURL }
    return flows.flows
  }

  /// The Flutter app's probe (`client.register(inhibitLogin: true)`): a server that registers accounts answers an
  /// empty registration with 401 and its interactive flows; one that does not answers 403.
  private func registrationSupported(homeserver: URL) async -> Bool {
    var request = URLRequest(url: homeserver.appending(path: "_matrix/client/v3/register"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data(#"{"inhibit_login":true}"#.utf8)
    guard case (let status, let data)? = await fetch(request), status == 401 else { return false }
    return (try? JSONDecoder().decode(InteractiveFlows.self, from: data))?.flows.isEmpty == false
  }
}

private struct WellKnown: Decodable {
  struct Homeserver: Decodable {
    let baseURL: String
    enum CodingKeys: String, CodingKey { case baseURL = "base_url" }
  }
  let homeserver: Homeserver
  enum CodingKeys: String, CodingKey { case homeserver = "m.homeserver" }
}

private struct LoginFlows: Decodable {
  struct Flow: Decodable {
    let type: String
    let identityProviders: [Provider]?
    enum CodingKeys: String, CodingKey {
      case type
      case identityProviders = "identity_providers"
    }
  }
  struct Provider: Decodable {
    let id: String
    let name: String
  }
  let flows: [Flow]
}

private struct InteractiveFlows: Decodable {
  struct Flow: Decodable {}
  let flows: [Flow]
}
