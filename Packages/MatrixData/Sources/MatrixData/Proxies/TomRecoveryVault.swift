import Domain
import Foundation

public actor TomRecoveryVault: RecoveryVault {
  private let clientProxy: @Sendable () async -> ClientProxy?
  private let capabilities: any ServerCapabilitiesRepository
  private let session: URLSession

  public init(
    authentication: MatrixAuthenticationRepository,
    capabilities: any ServerCapabilitiesRepository
  ) {
    self.init(
      clientProxy: { await authentication.clientProxy }, capabilities: capabilities,
      session: .shared)
  }

  init(
    clientProxy: @escaping @Sendable () async -> ClientProxy?,
    capabilities: any ServerCapabilitiesRepository, session: URLSession
  ) {
    self.clientProxy = clientProxy
    self.capabilities = capabilities
    self.session = session
  }

  public func fetchRecoveryKey() async throws(RecoveryVaultError) -> String? {
    guard let words = await words() else { throw .noServer }
    return try await words.fetch()
  }

  public func saveRecoveryKey(_ recoveryKey: String) async -> RecoveryVaultSaveResult {
    guard let words = await words() else { return .failed }
    return await words.save(recoveryKey)
  }

  public func deleteRecoveryKey() async {
    await words()?.delete()
  }

  private func words() async -> TomRecoveryWords? {
    guard let client = await clientProxy(), (try? client.userId) != nil,
      let token = try? client.client.session().accessToken,
      let tom = await capabilities.current().tom
    else { return nil }
    return TomRecoveryWords(tom: tom.baseURL, accessToken: token, session: session)
  }
}

/// ToM's `/_twake/recoveryWords`, byte for byte as the Flutter app and the web client call it (ADR 0017, ADR 0024):
/// `GET` answers `{ "words": … }` or 404 when ToM keeps nothing, `POST` keeps a key and answers 409 when ToM keeps
/// another one, `DELETE` lets it go.
struct TomRecoveryWords: Sendable {
  let tom: URL
  let accessToken: String
  let session: URLSession

  func fetch() async throws(RecoveryVaultError) -> String? {
    guard case (let data, let response)? = try? await session.data(for: request("GET")),
      let status = (response as? HTTPURLResponse)?.statusCode
    else { throw .unavailable }
    if status == 404 { return nil }
    guard status == 200 else { throw .unavailable }
    guard let words = (try? JSONDecoder().decode(Body.self, from: data))?.words, !words.isEmpty
    else { return nil }
    return words
  }

  func save(_ recoveryKey: String) async -> RecoveryVaultSaveResult {
    var post = request("POST")
    post.setValue("application/json", forHTTPHeaderField: "Content-Type")
    post.httpBody = try? JSONEncoder().encode(Body(words: recoveryKey))
    guard case (_, let response)? = try? await session.data(for: post),
      let status = (response as? HTTPURLResponse)?.statusCode
    else { return .failed }
    if (200..<300).contains(status) { return .saved }
    if status == 409 { return .alreadyKept }
    // Two keys posted at the same moment make ToM fail on its one-key-per-account rule instead of answering 409.
    if let kept = try? await fetch(), kept != recoveryKey { return .alreadyKept }
    return .failed
  }

  func delete() async {
    _ = try? await session.data(for: request("DELETE"))
  }

  private func request(_ method: String) -> URLRequest {
    var request = URLRequest(url: tom.appending(path: "_twake/recoveryWords"))
    request.httpMethod = method
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    return request
  }

  private struct Body: Codable {
    let words: String?
  }
}
