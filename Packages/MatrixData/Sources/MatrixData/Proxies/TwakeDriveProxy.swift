import AppShared
import Domain
import Foundation

protocol DriveTokenStore: Sendable {
  func load(account: String) -> String?
  func save(_ secret: String, account: String) throws
  func delete(account: String)
}

extension KeychainSecretStore: DriveTokenStore {}

public actor TwakeDriveProxy: TwakeDriveRepository {
  typealias Transport = @Sendable (URLRequest) async -> (Int, Data)?
  typealias Downloader = @Sendable (URL) async -> URL?

  struct AccountState: Sendable {
    let userId: String
    var discovery: TwakeSSO.Discovery?
    var pending: [String: TwakeSSO.Pending] = [:]
    var idToken: TwakeSSO.IdToken?
    var workplaceToken: String?
  }

  private let userId: @Sendable () async -> String?
  private let capabilities: any ServerCapabilitiesRepository
  private let tokens: any DriveTokenStore
  private let transport: Transport
  private let downloader: Downloader
  private let now: @Sendable () -> Date
  private var account: AccountState?

  public init(
    authentication: MatrixAuthenticationRepository,
    capabilities: any ServerCapabilitiesRepository, secrets: KeychainSecretStore
  ) {
    self.init(
      userId: { try? await authentication.clientProxy?.userId },
      capabilities: capabilities, tokens: secrets,
      transport: { request in
        guard let (data, response) = try? await URLSession.shared.data(for: request),
          let http = response as? HTTPURLResponse
        else { return nil }
        return (http.statusCode, data)
      },
      downloader: { url in
        guard let (file, response) = try? await URLSession.shared.download(from: url),
          let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
          response.url?.scheme == "https"
        else { return nil }
        return file
      },
      now: { Date() })
  }

  init(
    userId: @escaping @Sendable () async -> String?, capabilities: any ServerCapabilitiesRepository,
    tokens: any DriveTokenStore, transport: @escaping Transport, downloader: @escaping Downloader,
    now: @escaping @Sendable () -> Date
  ) {
    self.userId = userId
    self.capabilities = capabilities
    self.tokens = tokens
    self.transport = transport
    self.downloader = downloader
    self.now = now
  }

  static func tokenAccount(_ userId: String) -> String { "drive.\(userId)" }

  public static func forget(userId: String, in secrets: KeychainSecretStore) {
    secrets.delete(account: tokenAccount(userId))
  }

  public func isAvailable() async -> Bool {
    await capabilities.current().driveSignInIssuer != nil
  }

  public func signInRequest() async throws(DriveError) -> DriveSignInRequest {
    let (sso, _) = try await context()
    let discovery = try await discovery(sso)
    let pending = TwakeSSO.pending()
    guard let url = TwakeSSO.authorizeURL(discovery, pending: pending) else {
      throw .signInFailed
    }
    account?.pending[pending.state] = pending
    return DriveSignInRequest(
      url: url, callbackScheme: TwakeSSO.callbackScheme, state: pending.state)
  }

  public func completeSignIn(_ request: DriveSignInRequest, callback: URL) async throws(DriveError)
  {
    let (sso, userId) = try await context()
    guard let pending = account?.pending.removeValue(forKey: request.state) else {
      throw .signInFailed
    }
    let code = try TwakeSSO.code(from: callback, state: pending.state)
    let discovery = try await discovery(sso)
    let token = try await sso.exchange(
      code: code, pending: pending, discovery: discovery, now: now())
    try remember(token, userId: userId)
  }

  public func picker(_ options: DrivePickerOptions) async throws(DriveError) -> DrivePicker {
    let (sso, userId) = try await context()
    for attempt in 0..<2 {
      let idToken = try await validIdToken(sso, userId: userId, forceRefresh: attempt > 0)
      let api = WorkplaceAPI(
        platform: try TwakeSSO.platformURL(workplaceFqdn: idToken.workplaceFqdn),
        transport: transport)
      do throws(WorkplaceAPI.Failure) {
        let workplaceToken: String
        if let cached = account?.workplaceToken {
          workplaceToken = cached
        } else {
          workplaceToken = try await api.exchangeToken(idToken: idToken.value)
          account?.workplaceToken = workplaceToken
        }
        return try await api.createIntent(accessToken: workplaceToken, options: options)
      } catch {
        switch error {
        case .unauthorized: account?.workplaceToken = nil
        case .drive(let failure): throw failure
        }
      }
    }
    throw .exchangeRejected
  }

  public func download(_ document: DriveDocument, maxBytes: Int?) async throws(DriveError) -> URL {
    if let maxBytes, document.size > maxBytes { throw .tooLarge }
    guard let link = document.downloadLink, link.scheme == "https",
      let file = await downloader(link)
    else { throw .downloadFailed }
    let size =
      (try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))[.size]
        as? Int) ?? 0
    if let maxBytes, size > maxBytes { throw .tooLarge }
    let folder = FileManager.default.temporaryDirectory.appending(path: "drive_picks")
      .appending(path: UUID().uuidString)
    let target = folder.appending(path: Self.safeName(document.name))
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try FileManager.default.moveItem(at: file, to: target)
    } catch {
      throw .downloadFailed
    }
    return target
  }

  public func signOut() async {
    if let userId = await userId() { tokens.delete(account: Self.tokenAccount(userId)) }
    account = nil
  }

  static func safeName(_ name: String) -> String {
    let cleaned = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(
      of: ":", with: "_"
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "file" : cleaned
  }

  private func context() async throws(DriveError) -> (TwakeSSO, String) {
    guard let issuer = await capabilities.current().driveSignInIssuer else { throw .unavailable }
    guard let userId = await userId() else { throw .notSignedIn }
    if account?.userId != userId { account = AccountState(userId: userId) }
    return (TwakeSSO(issuer: issuer, transport: transport), userId)
  }

  private func discovery(_ sso: TwakeSSO) async throws(DriveError) -> TwakeSSO.Discovery {
    if let cached = account?.discovery { return cached }
    let found = try await sso.discover()
    account?.discovery = found
    return found
  }

  private func validIdToken(_ sso: TwakeSSO, userId: String, forceRefresh: Bool)
    async throws(DriveError) -> TwakeSSO.IdToken
  {
    if !forceRefresh, let token = account?.idToken, token.expiresAt > now().addingTimeInterval(60) {
      return token
    }
    guard
      let refreshToken = account?.idToken?.refreshToken
        ?? tokens.load(account: Self.tokenAccount(userId))
    else { throw .notSignedIn }
    let discovery = try await discovery(sso)
    do {
      let token = try await sso.refresh(refreshToken, discovery: discovery, now: now())
      try remember(token, userId: userId)
      return token
    } catch {
      account?.idToken = nil
      tokens.delete(account: Self.tokenAccount(userId))
      throw .notSignedIn
    }
  }

  private func remember(_ token: TwakeSSO.IdToken, userId: String) throws(DriveError) {
    account?.idToken = token
    account?.workplaceToken = nil
    if let refresh = token.refreshToken {
      do { try tokens.save(refresh, account: Self.tokenAccount(userId)) } catch {
        throw .signInFailed
      }
    }
  }
}
