import Foundation
import MatrixRustSDK

/// A request to the client-server API with the session's access token, for what the pinned SDK does not expose.
/// `path` is after `/_matrix/client/<version>/` (`v3` unless an endpoint is newer), already percent-encoded where it
/// holds ids.
enum ClientServerRequest {
  static func make(
    client: Client, path: String, method: String = "GET", json: [String: Any]? = nil,
    version: String = "v3"
  ) -> URLRequest? {
    guard let session = try? client.session(), let base = URL(string: session.homeserverUrl) else {
      return nil
    }
    let root =
      base.absoluteString.hasSuffix("/")
      ? String(base.absoluteString.dropLast()) : base.absoluteString
    guard let url = URL(string: root + "/_matrix/client/\(version)/" + path) else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
    if let json, let body = try? JSONSerialization.data(withJSONObject: json) {
      request.httpBody = body
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    return request
  }

  /// A Matrix id as one path segment.
  static func encode(_ id: String) -> String {
    id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
  }

  /// The JSON object of a 200 answer, or `nil`.
  static func object(_ request: URLRequest) async -> [String: Any]? {
    guard let (data, response) = try? await URLSession.shared.data(for: request),
      (response as? HTTPURLResponse)?.statusCode == 200
    else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }

  /// The status code and body of the answer, whatever the status; `nil` when no answer came.
  static func answer(_ request: URLRequest) async -> (Int, Data)? {
    guard let (data, response) = try? await URLSession.shared.data(for: request),
      let http = response as? HTTPURLResponse
    else { return nil }
    return (http.statusCode, data)
  }

  /// Whether the request answered 200.
  static func succeeds(_ request: URLRequest) async -> Bool {
    guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
    return (response as? HTTPURLResponse)?.statusCode == 200
  }
}
