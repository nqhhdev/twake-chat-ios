import Domain
import Foundation
import Testing

@testable import MatrixData

final class RoutedTransport: @unchecked Sendable {
  private let lock = NSLock()
  private var routes: [String: [(Int, String)]]
  private var _requests: [URLRequest] = []

  init(_ routes: [String: [(Int, String)]]) {
    self.routes = routes
  }

  var requests: [URLRequest] { lock.withLock { _requests } }

  func add(_ path: String, _ answer: (Int, String)) {
    lock.withLock { routes[path] = [answer] }
  }

  func requests(to path: String) -> [URLRequest] {
    requests.filter { $0.url?.path() == path }
  }

  var transport: TwakeDriveProxy.Transport {
    { request in
      self.lock.withLock {
        self._requests.append(request)
        let key = request.url?.path() ?? ""
        guard var answers = self.routes[key], !answers.isEmpty else {
          return (404, "{}".data(using: .utf8)!)
        }
        let answer = answers.count > 1 ? answers.removeFirst() : answers[0]
        self.routes[key] = answers
        return (answer.0, Data(answer.1.utf8))
      }
    }
  }
}

final class MemoryTokens: DriveTokenStore, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: String] = [:]

  func load(account: String) -> String? { lock.withLock { values[account] } }
  func save(_ secret: String, account: String) throws { lock.withLock { values[account] = secret } }
  func delete(account: String) { lock.withLock { values[account] = nil } }
}

struct FixedCapabilities: ServerCapabilitiesRepository {
  let value: ServerCapabilities
  func current() async -> ServerCapabilities { value }
  func refresh() async -> ServerCapabilities { value }
}

enum DriveFixtures {
  static let issuer = URL(string: "https://sso.example.org")!
  static let now = Date(timeIntervalSince1970: 1_800_000_000)

  static let discovery = """
    {"issuer":"https://sso.example.org","authorization_endpoint":"https://sso.example.org/authorize",\
    "token_endpoint":"https://sso.example.org/token"}
    """

  static func jwt(_ claims: [String: Any]) -> String {
    func part(_ object: [String: Any]) -> String {
      TwakeSSO.base64URL(try! JSONSerialization.data(withJSONObject: object))
    }
    return part(["alg": "RS256"]) + "." + part(claims) + ".signature"
  }

  static func idToken(
    nonce: String?, fqdn: String = "alice-drive.example.org", expiresIn: Double = 3600
  )
    -> String
  {
    var claims: [String: Any] = [
      "iss": "https://sso.example.org", "aud": "twake-chat-mobile", "sub": "alice",
      "exp": now.timeIntervalSince1970 + expiresIn, "workplaceFqdn": fqdn,
    ]
    if let nonce { claims["nonce"] = nonce }
    return jwt(claims)
  }

  static func tokenAnswer(_ idToken: String, refresh: String = "refresh-1") -> String {
    #"{"id_token":"\#(idToken)","refresh_token":"\#(refresh)","access_token":"x","token_type":"Bearer"}"#
  }

  static let intent = """
    {"data":{"id":"intent-1","type":"io.cozy.intents","attributes":{"action":"PICK","type":"io.cozy.files",\
    "permissions":["GET"],"client":"https://chat.example.org","services":[{"href":"https://alice-drive.example.org/pick?intent=intent-1"}]}}}
    """

  static func capabilities(drive: Bool, issuer: URL? = issuer) -> ServerCapabilities {
    ServerCapabilities(
      twakeChat: ServerCapabilities.TwakeChat(driveEnabled: drive), authenticationIssuer: issuer)
  }

  static let options = DrivePickerOptions(
    linkLabel: "Add link", attachLabel: "Attach", maxAttachmentBytes: 1000, isDark: false)
}

struct TwakeSSOTests {
  @Test func thePKCEChallengeFollowsRFC7636() {
    #expect(
      TwakeSSO.challenge(of: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    let pending = TwakeSSO.pending()
    #expect(pending.verifier.count >= 43)
    #expect(pending.state != pending.nonce)
  }

  @Test func theAuthorizeURLCarriesTheFlutterClientAndPKCE() throws {
    let object = try JSONSerialization.jsonObject(with: Data(DriveFixtures.discovery.utf8))
    let fields = try #require(object as? [String: Any])
    let discovery = try #require(TwakeSSO.discovery(from: fields, issuer: DriveFixtures.issuer))
    let pending = TwakeSSO.Pending(verifier: "v", state: "s", nonce: "n")
    let url = try #require(TwakeSSO.authorizeURL(discovery, pending: pending))
    let items = Dictionary(
      uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        ?? [])
        .map { ($0.name, $0.value ?? "") })
    #expect(url.host() == "sso.example.org")
    #expect(items["client_id"] == "twake-chat-mobile")
    #expect(items["redirect_uri"] == "twake.chat://login")
    #expect(items["scope"] == "openid profile email offline_access")
    #expect(items["code_challenge_method"] == "S256")
    #expect(items["code_challenge"] == TwakeSSO.challenge(of: "v"))
    #expect(items["state"] == "s")
    #expect(items["nonce"] == "n")
    #expect(items["response_type"] == "code")
  }

  @Test func aDiscoveryForAnotherIssuerOrOverHttpIsRefused() {
    let other: [String: Any] = [
      "issuer": "https://evil.example.org", "authorization_endpoint": "https://a/x",
      "token_endpoint": "https://a/y",
    ]
    #expect(TwakeSSO.discovery(from: other, issuer: DriveFixtures.issuer) == nil)
    let plain: [String: Any] = [
      "issuer": "https://sso.example.org/", "authorization_endpoint": "http://sso.example.org/a",
      "token_endpoint": "https://sso.example.org/t",
    ]
    #expect(TwakeSSO.discovery(from: plain, issuer: DriveFixtures.issuer) == nil)
  }

  @Test func theCallbackGivesTheCodeOnlyForItsOwnState() throws {
    #expect(
      try TwakeSSO.code(from: URL(string: "twake.chat://login?code=abc&state=s")!, state: "s")
        == "abc")
    #expect(throws: DriveError.signInFailed) {
      try TwakeSSO.code(from: URL(string: "twake.chat://login?code=abc&state=other")!, state: "s")
    }
    #expect(throws: DriveError.cancelled) {
      try TwakeSSO.code(
        from: URL(string: "twake.chat://login?error=access_denied&state=s")!, state: "s")
    }
    #expect(throws: DriveError.signInFailed) {
      try TwakeSSO.code(from: URL(string: "twake.chat://login?state=s")!, state: "s")
    }
  }

  @Test func theIdTokenIsCheckedLikeFlutter() throws {
    let discovery = TwakeSSO.Discovery(
      issuer: "https://sso.example.org", authorizationEndpoint: DriveFixtures.issuer,
      tokenEndpoint: DriveFixtures.issuer)
    let good: [String: Any] = [
      "id_token": DriveFixtures.idToken(nonce: "n"), "refresh_token": "r",
    ]
    let token = try TwakeSSO.verified(
      good, discovery: discovery, nonce: "n", now: DriveFixtures.now)
    #expect(token.workplaceFqdn == "alice-drive.example.org")
    #expect(token.refreshToken == "r")
    #expect(throws: DriveError.signInFailed) {
      try TwakeSSO.verified(good, discovery: discovery, nonce: "other", now: DriveFixtures.now)
    }
    let expired: [String: Any] = ["id_token": DriveFixtures.idToken(nonce: nil, expiresIn: -1)]
    #expect(throws: DriveError.signInFailed) {
      try TwakeSSO.verified(expired, discovery: discovery, nonce: nil, now: DriveFixtures.now)
    }
    let otherAudience: [String: Any] = [
      "id_token": DriveFixtures.jwt([
        "iss": "https://sso.example.org", "aud": ["twake-chat-mobile", "other"],
        "exp": DriveFixtures.now.timeIntervalSince1970 + 60,
      ])
    ]
    #expect(throws: DriveError.signInFailed) {
      try TwakeSSO.verified(otherAudience, discovery: discovery, nonce: nil, now: DriveFixtures.now)
    }
    let refreshed = try TwakeSSO.verified(
      ["id_token": DriveFixtures.idToken(nonce: nil)], discovery: discovery, nonce: nil,
      now: DriveFixtures.now, fallbackRefreshToken: "old")
    #expect(refreshed.refreshToken == "old")
  }

  @Test func theWorkplaceIsABareHostOverHttps() throws {
    #expect(
      try TwakeSSO.platformURL(workplaceFqdn: "Alice-Drive.example.org").absoluteString
        == "https://alice-drive.example.org")
    for bad in [nil, "", "evil.org:8443", "evil.org/path", "user@evil.org", "-a.org"] {
      #expect(throws: DriveError.workplaceUnknown) { try TwakeSSO.platformURL(workplaceFqdn: bad) }
    }
  }

  @Test func theTokenFormIsUrlEncoded() {
    let body = String(decoding: TwakeSSO.formBody(["b": "x y&z", "a": "1"]), as: UTF8.self)
    #expect(body == "a=1&b=x%20y%26z")
  }
}

struct WorkplaceAPITests {
  private let platform = URL(string: "https://alice-drive.example.org")!

  @Test func theTokenExchangeSendsTheIdTokenAsAnApp() async throws {
    let routes = RoutedTransport(["/auth/token_exchange": [(200, #"{"access_token":"wp-1"}"#)]])
    let api = WorkplaceAPI(platform: platform, transport: routes.transport)
    let token = try await api.exchangeToken(idToken: "id-1")
    #expect(token == "wp-1")
    let request = try #require(routes.requests.first)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString == "https://alice-drive.example.org/auth/token_exchange")
    let body = try #require(
      try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String])
    #expect(body == ["id_token": "id-1", "exchange_type": "app"])
  }

  @Test func theIntentIsAJsonApiPickWithABearerToken() async throws {
    let routes = RoutedTransport(["/intents": [(201, DriveFixtures.intent)]])
    let api = WorkplaceAPI(platform: platform, transport: routes.transport)
    let picker = try await api.createIntent(accessToken: "wp-1", options: DriveFixtures.options)
    #expect(picker.intentId == "intent-1")
    #expect(picker.client == "https://chat.example.org")
    #expect(picker.origin == "https://alice-drive.example.org")
    let request = try #require(routes.requests.first)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer wp-1")
    #expect(request.url?.query() == "force_session_id=true")
    let body = try #require(
      try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
    let data = try #require(body["data"] as? [String: Any])
    #expect(data["type"] as? String == "io.cozy.intents")
    let attributes = try #require(data["attributes"] as? [String: Any])
    #expect(attributes["action"] as? String == "PICK")
    #expect(attributes["type"] as? String == "io.cozy.files")
    #expect(attributes["permissions"] as? [String] == ["GET"])
    let config = try #require(attributes["data"] as? [String: Any])
    #expect((config["sharingLink"] as? [String: Any])?["label"] as? String == "Add link")
    #expect((config["downloadLink"] as? [String: Any])?["maxFileSize"] as? Int == 1000)
    #expect((config["theme"] as? [String: Any])?["type"] as? String == "light")
    let acknowledgement = try #require(
      try JSONSerialization.jsonObject(with: Data(picker.acknowledgement.utf8)) as? [String: Any])
    #expect((acknowledgement["sharingLink"] as? [String: Any])?["label"] as? String == "Add link")
  }

  @Test func anExpiredWorkplaceTokenIsToldApart() async {
    let routes = RoutedTransport([
      "/intents": [(401, "{}")], "/auth/token_exchange": [(400, "{}")],
    ])
    let api = WorkplaceAPI(platform: platform, transport: routes.transport)
    await #expect(throws: WorkplaceAPI.Failure.unauthorized) {
      try await api.createIntent(accessToken: "old", options: DriveFixtures.options)
    }
    await #expect(throws: WorkplaceAPI.Failure.drive(.exchangeRejected)) {
      try await api.exchangeToken(idToken: "id")
    }
  }

  @Test func anIntentWithoutAClientOrOverHttpIsRefused() {
    let noClient = Data(
      #"{"data":{"id":"i","attributes":{"client":"*","services":[{"href":"https://d.example.org/x"}]}}}"#
        .utf8)
    #expect(WorkplaceAPI.picker(from: noClient, acknowledgement: "{}") == nil)
    let plain = Data(
      #"{"data":{"id":"i","attributes":{"client":"https://c","services":[{"href":"http://d.example.org/x"}]}}}"#
        .utf8)
    #expect(WorkplaceAPI.picker(from: plain, acknowledgement: "{}") == nil)
  }
}

struct TwakeDriveProxyTests {
  private func proxy(
    _ routes: RoutedTransport, tokens: MemoryTokens = MemoryTokens(), drive: Bool = true,
    issuer: URL? = DriveFixtures.issuer, userId: String? = "@alice:example.org"
  ) -> TwakeDriveProxy {
    TwakeDriveProxy(
      userId: { userId },
      capabilities: FixedCapabilities(
        value: DriveFixtures.capabilities(drive: drive, issuer: issuer)),
      tokens: tokens, transport: routes.transport, downloader: { _ in nil },
      now: { DriveFixtures.now })
  }

  @Test func driveShowsOnlyWhenTheServerTurnsItOnWithAnIssuer() async {
    let routes = RoutedTransport([:])
    #expect(await proxy(routes).isAvailable())
    #expect(!(await proxy(routes, drive: false).isAvailable()))
    #expect(!(await proxy(routes, issuer: nil).isAvailable()))
    await #expect(throws: DriveError.unavailable) {
      try await proxy(routes, drive: false).signInRequest()
    }
    #expect(routes.requests.isEmpty)
  }

  @Test func signingInThenPickingRunsTheWholeFlow() async throws {
    let routes = RoutedTransport([
      "/.well-known/openid-configuration": [(200, DriveFixtures.discovery)],
      "/auth/token_exchange": [(200, #"{"access_token":"wp-1"}"#)],
      "/intents": [(201, DriveFixtures.intent)],
    ])
    let tokens = MemoryTokens()
    let drive = proxy(routes, tokens: tokens)
    let request = try await drive.signInRequest()
    #expect(request.callbackScheme == "twake.chat")
    let nonce = try #require(
      URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?
        .first { $0.name == "nonce" }?.value)
    routes.add("/token", (200, DriveFixtures.tokenAnswer(DriveFixtures.idToken(nonce: nonce))))
    try await drive.completeSignIn(
      request, callback: URL(string: "twake.chat://login?code=c1&state=\(request.state)")!)
    #expect(tokens.load(account: "drive.@alice:example.org") == "refresh-1")
    let tokenForm = String(
      decoding: routes.requests(to: "/token").first?.httpBody ?? Data(), as: UTF8.self)
    #expect(tokenForm.contains("grant_type=authorization_code"))
    #expect(tokenForm.contains("code=c1"))
    #expect(tokenForm.contains("code_verifier="))

    let picker = try await drive.picker(DriveFixtures.options)
    #expect(picker.intentId == "intent-1")
    #expect(
      routes.requests(to: "/auth/token_exchange").first?.url?.host() == "alice-drive.example.org")
    _ = try await drive.picker(DriveFixtures.options)
    #expect(routes.requests(to: "/auth/token_exchange").count == 1)
  }

  @Test func aCallbackForAnUnknownSignInIsRefused() async throws {
    let routes = RoutedTransport([
      "/.well-known/openid-configuration": [(200, DriveFixtures.discovery)]
    ])
    let drive = proxy(routes)
    let request = try await drive.signInRequest()
    let forged = DriveSignInRequest(url: request.url, callbackScheme: "twake.chat", state: "forged")
    await #expect(throws: DriveError.signInFailed) {
      try await drive.completeSignIn(
        forged, callback: URL(string: "twake.chat://login?code=c&state=forged")!)
    }
  }

  @Test func aStoredRefreshTokenSignsInSilentlyAndAnExpiredWorkplaceTokenIsRenewed() async throws {
    let tokens = MemoryTokens()
    try tokens.save("refresh-0", account: "drive.@alice:example.org")
    let routes = RoutedTransport([
      "/.well-known/openid-configuration": [(200, DriveFixtures.discovery)],
      "/token": [
        (200, DriveFixtures.tokenAnswer(DriveFixtures.idToken(nonce: nil), refresh: "refresh-2"))
      ],
      "/auth/token_exchange": [
        (200, #"{"access_token":"wp-1"}"#), (200, #"{"access_token":"wp-2"}"#),
      ],
      "/intents": [(401, "{}"), (201, DriveFixtures.intent)],
    ])
    let picker = try await proxy(routes, tokens: tokens).picker(DriveFixtures.options)
    #expect(picker.intentId == "intent-1")
    #expect(routes.requests(to: "/auth/token_exchange").count == 2)
    #expect(
      routes.requests(to: "/intents").last?.value(forHTTPHeaderField: "Authorization")
        == "Bearer wp-2")
    let refreshForm = String(
      decoding: routes.requests(to: "/token").first?.httpBody ?? Data(), as: UTF8.self)
    #expect(refreshForm.contains("grant_type=refresh_token"))
    #expect(refreshForm.contains("refresh_token=refresh-0"))
    #expect(tokens.load(account: "drive.@alice:example.org") == "refresh-2")
  }

  @Test func withoutATokenThePickerAsksToSignIn() async {
    let routes = RoutedTransport([:])
    await #expect(throws: DriveError.notSignedIn) {
      try await proxy(routes).picker(DriveFixtures.options)
    }
  }

  @Test func aRejectedRefreshForgetsTheToken() async throws {
    let tokens = MemoryTokens()
    try tokens.save("dead", account: "drive.@alice:example.org")
    let routes = RoutedTransport([
      "/.well-known/openid-configuration": [(200, DriveFixtures.discovery)],
      "/token": [(400, #"{"error":"invalid_grant"}"#)],
    ])
    await #expect(throws: DriveError.notSignedIn) {
      try await proxy(routes, tokens: tokens).picker(DriveFixtures.options)
    }
    #expect(tokens.load(account: "drive.@alice:example.org") == nil)
  }

  @Test func tokensAreKeptPerAccountAndSigningOutForgetsThem() async throws {
    let tokens = MemoryTokens()
    try tokens.save("alice", account: "drive.@alice:example.org")
    try tokens.save("bob", account: "drive.@bob:example.org")
    await proxy(RoutedTransport([:]), tokens: tokens).signOut()
    #expect(tokens.load(account: "drive.@alice:example.org") == nil)
    #expect(tokens.load(account: "drive.@bob:example.org") == "bob")
  }

  @Test func aFileOverTheLimitIsNotDownloaded() async {
    let document = DriveDocument(
      id: "1", name: "big.bin", size: 2000, mimeType: nil, sharingLink: nil,
      downloadLink: URL(string: "https://d.example.org/big"))
    await #expect(throws: DriveError.tooLarge) {
      try await proxy(RoutedTransport([:])).download(document, maxBytes: 1000)
    }
    #expect(TwakeDriveProxy.safeName("../a/b:c") == ".._a_b_c")
    #expect(TwakeDriveProxy.safeName("  ") == "file")
  }

  @Test func theWellKnownTurnsDriveOnWithItsIssuer() {
    let wellKnown = Data(
      #"{"m.homeserver":{"base_url":"https://matrix.example.org"},"m.authentication":{"issuer":"https://sso.example.org"},"app.twake.chat":{"enable_twake_drive":true}}"#
        .utf8)
    let on = ServerCapabilitiesParser.capabilities(
      wellKnown: wellKnown, versions: nil, serverName: "example.org", homeserver: nil,
      build: BuildServices())
    #expect(on.driveSignInIssuer?.absoluteString == "https://sso.example.org")
    let off = ServerCapabilitiesParser.capabilities(
      wellKnown: Data(#"{"m.authentication":{"issuer":"https://sso.example.org"}}"#.utf8),
      versions: nil, serverName: "example.org", homeserver: nil, build: BuildServices())
    #expect(off.driveSignInIssuer == nil)
    #expect(off.authenticationIssuer != nil)
  }
}
