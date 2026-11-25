import Domain
import Foundation

public actor IdentityServerProxy: IdentityRepository {
  static let lookupBatch = 500

  private let clientProxy: @Sendable () async -> ClientProxy?
  private let transport: IdentityService.Transport
  private let language: String
  private var service: IdentityService??
  private var token: String?
  private var pepper: String?

  public init(
    authentication: MatrixAuthenticationRepository,
    language: String = Locale.current.language.languageCode?.identifier ?? "en"
  ) {
    clientProxy = { await authentication.clientProxy }
    transport = { request in
      guard let (data, response) = try? await URLSession.shared.data(for: request),
        let http = response as? HTTPURLResponse
      else { return nil }
      return (http.statusCode, data)
    }
    self.language = language
  }

  public func status() async -> IdentityServerStatus {
    guard let client = await clientProxy(), let service = await service(client),
      let policies = try? await service.policies(language: language)
    else { return .unavailable }
    let accepted = await acceptedTerms(client)
    if policies.allSatisfy({ accepted.contains($0.url.absoluteString) }) { return .ready }
    return .needsConsent(server: service.idServer, policies: policies)
  }

  public func acceptTerms(_ policies: [IdentityPolicy]) async throws(IdentityError) {
    let (client, service) = try await access()
    let urls = policies.map(\.url)
    try await withToken(client, service) { token throws(IdentityError) in
      try await service.accept(urls, token: token)
    }
    let accepted = await acceptedTerms(client)
    let all = Array(Set(accepted).union(urls.map(\.absoluteString))).sorted()
    if let userId = try? client.userId,
      let request = ClientServerRequest.make(
        client: client.client,
        path: "user/\(ClientServerRequest.encode(userId))/account_data/m.accepted_terms",
        method: "PUT", json: ["accepted": all])
    {
      _ = await ClientServerRequest.answer(request)
    }
  }

  public func lookup(_ addresses: [ContactAddress]) async throws(IdentityError)
    -> [ContactAddress: String]
  {
    guard !addresses.isEmpty else { return [:] }
    let (client, service) = try await access()
    var found: [ContactAddress: String] = [:]
    let unique = Array(Set(addresses))
    for start in stride(from: 0, to: unique.count, by: Self.lookupBatch) {
      let batch = Array(unique[start..<min(start + Self.lookupBatch, unique.count)])
      let mappings = try await withToken(client, service) { token throws(IdentityError) in
        try await self.lookup(batch, service: service, token: token)
      }
      for address in batch {
        guard let pepper, let userId = mappings[IdentityService.hash(address, pepper: pepper)]
        else { continue }
        found[address] = userId
      }
    }
    return found
  }

  public func invite(_ address: ContactAddress, roomId: String) async throws(IdentityError) {
    let (client, service) = try await access()
    try await withToken(client, service) { token throws(IdentityError) in
      guard
        let request = ClientServerRequest.make(
          client: client.client, path: "rooms/\(ClientServerRequest.encode(roomId))/invite",
          method: "POST",
          json: Self.inviteBody(address, idServer: service.idServer, token: token))
      else { throw .notSignedIn }
      try await Self.matrixAnswer(request)
    }
  }

  public func startDirectChat(inviting address: ContactAddress) async throws(IdentityError)
    -> String
  {
    let (client, service) = try await access()
    return try await withToken(client, service) { token throws(IdentityError) in
      guard
        let request = ClientServerRequest.make(
          client: client.client, path: "createRoom", method: "POST",
          json: Self.directChatBody(address, idServer: service.idServer, token: token))
      else { throw .notSignedIn }
      guard let roomId = try await Self.matrixAnswer(request)["room_id"] as? String else {
        throw .requestFailed
      }
      return roomId
    }
  }

  static func inviteBody(_ address: ContactAddress, idServer: String, token: String) -> [String:
    String]
  {
    [
      "id_server": idServer, "id_access_token": token, "medium": address.medium,
      "address": address.matrixAddress,
    ]
  }

  static func directChatBody(_ address: ContactAddress, idServer: String, token: String)
    -> [String: Any]
  {
    [
      "is_direct": true, "preset": "trusted_private_chat", "visibility": "private",
      "invite_3pid": [inviteBody(address, idServer: idServer, token: token)],
      "initial_state": [
        [
          "type": "m.room.encryption", "state_key": "",
          "content": ["algorithm": "m.megolm.v1.aes-sha2"],
        ]
      ],
    ]
  }

  @discardableResult
  private static func matrixAnswer(_ request: URLRequest) async throws(IdentityError) -> [String:
    Any]
  {
    guard let (status, data) = await ClientServerRequest.answer(request) else {
      throw .requestFailed
    }
    guard status == 200 else {
      throw IdentityService.errorCode(data) == "M_UNAUTHORIZED" ? .notSignedIn : .requestFailed
    }
    return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
  }

  private func lookup(_ batch: [ContactAddress], service: IdentityService, token: String)
    async throws(IdentityError) -> [String: String]
  {
    for attempt in 0..<2 {
      let pepper = try await currentPepper(service, token: token, refresh: attempt > 0)
      let hashes = batch.map { IdentityService.hash($0, pepper: pepper) }
      switch try await service.lookup(hashes: hashes, pepper: pepper, token: token) {
      case .mappings(let mappings): return mappings
      case .invalidPepper: continue
      }
    }
    throw .requestFailed
  }

  private func currentPepper(_ service: IdentityService, token: String, refresh: Bool)
    async throws(IdentityError) -> String
  {
    if let pepper, !refresh { return pepper }
    let fresh = try await service.pepper(token: token)
    pepper = fresh
    return fresh
  }

  private func withToken<T: Sendable>(
    _ client: ClientProxy, _ service: IdentityService,
    _ body: (String) async throws(IdentityError) -> T
  ) async throws(IdentityError) -> T {
    do {
      return try await body(try await currentToken(client, service))
    } catch .notSignedIn {
      token = nil
      return try await body(try await currentToken(client, service))
    }
  }

  private func currentToken(_ client: ClientProxy, _ service: IdentityService)
    async throws(IdentityError) -> String
  {
    if let token { return token }
    guard let userId = try? client.userId,
      let request = ClientServerRequest.make(
        client: client.client,
        path: "user/\(ClientServerRequest.encode(userId))/openid/request_token", method: "POST",
        json: [:]),
      let (status, openID) = await ClientServerRequest.answer(request), status == 200
    else { throw .requestFailed }
    let fresh = try await service.register(openID: openID)
    token = fresh
    let accepted = Set(await acceptedTerms(client))
    if let policies = try? await service.policies(language: language) {
      let known = policies.map(\.url).filter { accepted.contains($0.absoluteString) }
      if !known.isEmpty { try? await service.accept(known, token: fresh) }
    }
    return fresh
  }

  private func access() async throws(IdentityError) -> (ClientProxy, IdentityService) {
    guard let client = await clientProxy() else { throw .notSignedIn }
    guard let service = await service(client) else { throw .unavailable }
    return (client, service)
  }

  private func service(_ client: ClientProxy) async -> IdentityService? {
    if let service { return service }
    let found = await discover(client).flatMap {
      IdentityService(baseURL: $0, transport: transport)
    }
    service = .some(found)
    return found
  }

  private func discover(_ client: ClientProxy) async -> URL? {
    guard let userId = try? client.userId else { return nil }
    if let request = ClientServerRequest.make(
      client: client.client,
      path: "user/\(ClientServerRequest.encode(userId))/account_data/m.identity_server"),
      let (status, data) = await ClientServerRequest.answer(request), status == 200,
      let chosen = IdentityService.baseURL(fromAccountData: data)
    {
      return chosen
    }
    guard let serverName = userId.split(separator: ":", maxSplits: 1).last,
      let url = URL(string: "https://\(serverName)/.well-known/matrix/client"),
      let (status, data) = await transport(URLRequest(url: url)), status == 200
    else { return nil }
    return IdentityService.baseURL(fromWellKnown: data)
  }

  private func acceptedTerms(_ client: ClientProxy) async -> [String] {
    guard let userId = try? client.userId,
      let request = ClientServerRequest.make(
        client: client.client,
        path: "user/\(ClientServerRequest.encode(userId))/account_data/m.accepted_terms"),
      let object = await ClientServerRequest.object(request)
    else { return [] }
    return object["accepted"] as? [String] ?? []
  }
}
