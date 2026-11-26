import CryptoKit
import Domain
import Foundation

struct TwakeSSO: Sendable {
  typealias Transport = @Sendable (URLRequest) async -> (Int, Data)?

  struct Discovery: Sendable, Equatable {
    let issuer: String
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
  }

  struct Pending: Sendable, Equatable {
    let verifier: String
    let state: String
    let nonce: String
  }

  struct IdToken: Sendable, Equatable {
    let value: String
    let expiresAt: Date
    let workplaceFqdn: String?
    let refreshToken: String?
  }

  static let clientId = "twake-chat-mobile"
  static let redirectURI = "twake.chat://login"
  static let callbackScheme = "twake.chat"
  static let scope = "openid profile email offline_access"

  let issuer: URL
  let transport: Transport

  func discover() async throws(DriveError) -> Discovery {
    let url = URL(
      string: Self.withoutTrailingSlash(issuer.absoluteString) + "/.well-known/openid-configuration"
    )
    guard let url, url.scheme == "https" else { throw .unavailable }
    guard let (status, data) = await transport(URLRequest(url: url)), status == 200,
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let discovery = Self.discovery(from: object, issuer: issuer)
    else { throw .signInFailed }
    return discovery
  }

  static func discovery(from object: [String: Any], issuer: URL) -> Discovery? {
    guard let name = object["issuer"] as? String,
      withoutTrailingSlash(name) == withoutTrailingSlash(issuer.absoluteString),
      let authorization = (object["authorization_endpoint"] as? String).flatMap(URL.init(string:)),
      let token = (object["token_endpoint"] as? String).flatMap(URL.init(string:)),
      authorization.scheme == "https", token.scheme == "https"
    else { return nil }
    return Discovery(issuer: name, authorizationEndpoint: authorization, tokenEndpoint: token)
  }

  static func pending() -> Pending {
    Pending(verifier: randomToken(), state: randomToken(), nonce: randomToken())
  }

  static func challenge(of verifier: String) -> String {
    base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
  }

  static func authorizeURL(_ discovery: Discovery, pending: Pending) -> URL? {
    var components = URLComponents(
      url: discovery.authorizationEndpoint, resolvingAgainstBaseURL: false)
    let existing = components?.queryItems ?? []
    components?.queryItems =
      existing + [
        URLQueryItem(name: "response_type", value: "code"),
        URLQueryItem(name: "client_id", value: clientId),
        URLQueryItem(name: "redirect_uri", value: redirectURI),
        URLQueryItem(name: "scope", value: scope),
        URLQueryItem(name: "code_challenge", value: challenge(of: pending.verifier)),
        URLQueryItem(name: "code_challenge_method", value: "S256"),
        URLQueryItem(name: "state", value: pending.state),
        URLQueryItem(name: "nonce", value: pending.nonce),
      ]
    return components?.url
  }

  static func code(from callback: URL, state: String) throws(DriveError) -> String {
    let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let value = { (name: String) in items.first { $0.name == name }?.value }
    if value("error") == "access_denied" { throw .cancelled }
    guard value("error") == nil, value("state") == state, let code = value("code"), !code.isEmpty
    else { throw .signInFailed }
    return code
  }

  func exchange(code: String, pending: Pending, discovery: Discovery, now: Date)
    async throws(DriveError)
    -> IdToken
  {
    let answer = try await postToken(
      discovery,
      [
        "grant_type": "authorization_code", "code": code, "code_verifier": pending.verifier,
        "redirect_uri": Self.redirectURI, "client_id": Self.clientId,
      ])
    return try Self.verified(answer, discovery: discovery, nonce: pending.nonce, now: now)
  }

  func refresh(_ refreshToken: String, discovery: Discovery, now: Date) async throws(DriveError)
    -> IdToken
  {
    let answer = try await postToken(
      discovery,
      ["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": Self.clientId])
    return try Self.verified(
      answer, discovery: discovery, nonce: nil, now: now, fallbackRefreshToken: refreshToken)
  }

  static func formBody(_ form: [String: String]) -> Data {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return Data(
      form.keys.sorted().map { key in
        let value = form[key] ?? ""
        return "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
      }.joined(separator: "&").utf8)
  }

  static func verified(
    _ answer: [String: Any], discovery: Discovery, nonce: String?, now: Date,
    fallbackRefreshToken: String? = nil
  ) throws(DriveError) -> IdToken {
    guard let idToken = answer["id_token"] as? String, let claims = claims(of: idToken),
      claims["iss"] as? String == discovery.issuer
    else { throw .signInFailed }
    let audience: [String] =
      (claims["aud"] as? [String]) ?? (claims["aud"] as? String).map { [$0] } ?? []
    let authorizedParty = claims["azp"] as? String
    guard audience.contains(clientId),
      audience.count == 1 || authorizedParty == clientId,
      authorizedParty == nil || authorizedParty == clientId,
      let expiry = (claims["exp"] as? NSNumber)?.doubleValue,
      Date(timeIntervalSince1970: expiry) > now,
      nonce == nil || claims["nonce"] as? String == nonce
    else { throw .signInFailed }
    return IdToken(
      value: idToken, expiresAt: Date(timeIntervalSince1970: expiry),
      workplaceFqdn: claims["workplaceFqdn"] as? String,
      refreshToken: answer["refresh_token"] as? String ?? fallbackRefreshToken)
  }

  static func claims(of jwt: String) -> [String: Any]? {
    let parts = jwt.split(separator: ".")
    guard parts.count == 3 else { return nil }
    var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    while payload.count % 4 != 0 { payload += "=" }
    guard let data = Data(base64Encoded: payload) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }

  static func platformURL(workplaceFqdn: String?) throws(DriveError) -> URL {
    let host = workplaceFqdn?.lowercased() ?? ""
    guard host.wholeMatch(of: #/[a-z0-9]([a-z0-9.-]*[a-z0-9])?/#) != nil,
      let url = URL(string: "https://\(host)")
    else { throw .workplaceUnknown }
    return url
  }

  private func postToken(_ discovery: Discovery, _ form: [String: String]) async throws(DriveError)
    -> [String: Any]
  {
    var request = URLRequest(url: discovery.tokenEndpoint)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = Self.formBody(form)
    guard let (status, data) = await transport(request), status == 200,
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw .signInFailed }
    return object
  }

  private static func randomToken() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
    return base64URL(Data(bytes))
  }

  static func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }

  private static func withoutTrailingSlash(_ text: String) -> String {
    var text = text
    while text.hasSuffix("/") { text.removeLast() }
    return text
  }
}
