import Foundation

/// The people search of a Twake server (ToM), as the Flutter app's `TomContactAPI` does it: the homeserver's
/// `.well-known/matrix/client` names the ToM server under `t.server`, and `POST /_twake/identity/v1/lookup/match`
/// searches its address book by name, mail, phone or uid with the user's Matrix access token. A server without
/// `t.server` has no such search; `PeopleProxy` then uses the Matrix user directory alone. Nothing here logs.
struct TwakeContactLookup: Sendable {
  struct Match: Sendable, Equatable {
    let userId: String
    let displayName: String?
  }

  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func search(_ text: String, limit: Int, tom: URL, serverName: String, accessToken: String)
    async throws -> [Match]
  {
    var request = URLRequest(url: tom.appending(path: "_twake/identity/v1/lookup/match"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONEncoder().encode(
      LookupRequest(
        scope: ["mail", "uid", "mobile", "cn", "displayName"],
        fields: ["uid", "mobile", "mail", "cn", "displayName"],
        val: text, limit: limit, offset: 0))
    let (data, response) = try await session.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw URLError(.badServerResponse)
    }
    let found = try JSONDecoder().decode(LookupResponse.self, from: data)
    return found.matches.map { contact in
      // `address` is the Matrix id; a contact without one is `@uid:server`.
      let userId =
        contact.address.flatMap { $0.hasPrefix("@") ? $0 : nil } ?? "@\(contact.uid):\(serverName)"
      return Match(userId: userId, displayName: contact.displayName ?? contact.cn)
    }
  }

  /// Who sees the user's e-mail and phone: `GET /_twake/v1/user_info/{id}/visibility`; `nil` when ToM has none.
  func visibility(of userId: String, tom: URL, accessToken: String) async -> String? {
    var request = URLRequest(url: Self.visibilityURL(userId, tom: tom))
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    guard case (let data, let response)? = try? await session.data(for: request),
      (response as? HTTPURLResponse)?.statusCode == 200,
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return object["visibility"] as? String
  }

  /// Sets it, for the e-mail and the phone together, as the web client does.
  func setVisibility(_ visibility: String, of userId: String, tom: URL, accessToken: String) async
    -> Bool
  {
    var request = URLRequest(url: Self.visibilityURL(userId, tom: tom))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.httpBody = try? JSONSerialization.data(withJSONObject: [
      "matrix_id": userId, "visibility": visibility, "visible_fields": ["email", "phone"],
    ])
    guard case (_, let response)? = try? await session.data(for: request) else { return false }
    return (response as? HTTPURLResponse)?.statusCode == 200
  }

  func language(of userId: String, tom: URL, accessToken: String) async -> String? {
    var request = URLRequest(
      url: tom.appending(path: "_twake/v1/user_info").appending(path: userId))
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    guard case (let data, let response)? = try? await session.data(for: request),
      (response as? HTTPURLResponse)?.statusCode == 200,
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let language = object["language"] as? String, !language.isEmpty
    else { return nil }
    return language
  }

  static func visibilityURL(_ userId: String, tom: URL) -> URL {
    tom.appending(path: "_twake/v1/user_info").appending(path: userId).appending(path: "visibility")
  }

  private struct LookupRequest: Encodable {
    let scope: [String]
    let fields: [String]
    let val: String
    let limit: Int
    let offset: Int
  }

  private struct LookupResponse: Decodable {
    struct Contact: Decodable {
      let uid: String
      let address: String?
      let cn: String?
      let displayName: String?
    }
    let matches: [Contact]
  }
}
