import CryptoKit
import Domain
import Foundation

struct IdentityService: Sendable {
  typealias Transport = @Sendable (URLRequest) async -> (Int, Data)?

  enum LookupAnswer: Sendable, Equatable {
    case mappings([String: String])
    case invalidPepper
  }

  let baseURL: URL
  let transport: Transport

  init?(baseURL: URL, transport: @escaping Transport) {
    guard baseURL.scheme == "https", baseURL.host() != nil else { return nil }
    self.baseURL = baseURL
    self.transport = transport
  }

  var idServer: String {
    let host = baseURL.host() ?? ""
    return baseURL.port.map { "\(host):\($0)" } ?? host
  }

  func register(openID: Data) async throws(IdentityError) -> String {
    var request = request("account/register", method: "POST", token: nil)
    request.httpBody = openID
    let object = try await send(request)
    guard let token = (object["token"] ?? object["access_token"]) as? String else {
      throw .requestFailed
    }
    return token
  }

  func policies(language: String) async throws(IdentityError) -> [IdentityPolicy] {
    let object = try await send(request("terms", method: "GET", token: nil))
    return Self.policies(from: object, language: language)
  }

  func accept(_ urls: [URL], token: String) async throws(IdentityError) {
    var request = request("terms", method: "POST", token: token)
    request.httpBody = try? JSONSerialization.data(withJSONObject: [
      "user_accepts": urls.map(\.absoluteString)
    ])
    _ = try await send(request)
  }

  func pepper(token: String) async throws(IdentityError) -> String {
    let object = try await send(request("hash_details", method: "GET", token: token))
    guard let algorithms = object["algorithms"] as? [String], algorithms.contains("sha256"),
      let pepper = object["lookup_pepper"] as? String
    else { throw .unavailable }
    return pepper
  }

  func lookup(hashes: [String], pepper: String, token: String) async throws(IdentityError)
    -> LookupAnswer
  {
    var request = request("lookup", method: "POST", token: token)
    request.httpBody = try? JSONSerialization.data(withJSONObject: Self.lookupBody(hashes, pepper))
    guard let (status, data) = await transport(request) else { throw .requestFailed }
    if status == 400, Self.errorCode(data) == "M_INVALID_PEPPER" { return .invalidPepper }
    guard status == 200 else { throw Self.error(status: status, data: data) }
    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    return .mappings(object?["mappings"] as? [String: String] ?? [:])
  }

  static func lookupBody(_ hashes: [String], _ pepper: String) -> [String: Any] {
    ["addresses": hashes, "algorithm": "sha256", "pepper": pepper]
  }

  static func hash(_ address: ContactAddress, pepper: String) -> String {
    let digest = SHA256.hash(
      data: Data("\(address.matrixAddress) \(address.medium) \(pepper)".utf8))
    return Data(digest).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  static func policies(from object: [String: Any], language: String) -> [IdentityPolicy] {
    guard let policies = object["policies"] as? [String: Any] else { return [] }
    return policies.keys.sorted().compactMap { key in
      guard let policy = policies[key] as? [String: Any] else { return nil }
      let translations = policy.filter { $0.key != "version" }.compactMapValues {
        $0 as? [String: Any]
      }
      guard
        let chosen = translations[language] ?? translations["en"]
          ?? translations.keys.sorted().first.flatMap({ translations[$0] }),
        let urlString = chosen["url"] as? String, let url = URL(string: urlString)
      else { return nil }
      return IdentityPolicy(id: key, title: chosen["name"] as? String ?? key, url: url)
    }
  }

  static func baseURL(fromWellKnown data: Data) -> URL? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let server = object["m.identity_server"] as? [String: Any],
      let base = server["base_url"] as? String
    else { return nil }
    return URL(string: base)
  }

  static func baseURL(fromAccountData data: Data) -> URL?? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    guard let base = object["base_url"] as? String else { return .some(nil) }
    return .some(URL(string: base))
  }

  static func error(status: Int, data: Data) -> IdentityError {
    switch (status, errorCode(data)) {
    case (403, "M_TERMS_NOT_SIGNED"): .termsNotAccepted
    case (401, _): .notSignedIn
    default: .requestFailed
    }
  }

  static func errorCode(_ data: Data) -> String? {
    (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["errcode"] as? String
  }

  private func request(_ path: String, method: String, token: String?) -> URLRequest {
    var request = URLRequest(
      url: baseURL.appending(path: "_matrix/identity/v2").appending(path: path))
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    return request
  }

  private func send(_ request: URLRequest) async throws(IdentityError) -> [String: Any] {
    guard let (status, data) = await transport(request) else { throw .requestFailed }
    guard status == 200 else { throw Self.error(status: status, data: data) }
    return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
  }
}
