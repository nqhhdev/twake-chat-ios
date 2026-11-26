import Domain
import Foundation

public actor ServerCapabilitiesProxy: ServerCapabilitiesRepository {
  struct Account: Sendable {
    let userId: String
    let homeserver: URL?
  }

  private let account: @Sendable () async -> Account?
  private let session: URLSession
  private let build: BuildServices
  private var cached: (userId: String, capabilities: ServerCapabilities)?
  private var loading: (userId: String, task: Task<ServerCapabilities, Never>)?

  public init(authentication: MatrixAuthenticationRepository, build: BuildServices) {
    self.init(
      account: {
        guard let client = await authentication.clientProxy, let userId = try? client.userId
        else { return nil }
        let homeserver = (try? client.client.session().homeserverUrl).flatMap(URL.init(string:))
        return Account(userId: userId, homeserver: homeserver)
      }, session: .shared, build: build)
  }

  init(
    account: @escaping @Sendable () async -> Account?, session: URLSession, build: BuildServices
  ) {
    self.account = account
    self.session = session
    self.build = build
  }

  public func current() async -> ServerCapabilities {
    guard let account = await account() else { return ServerCapabilities(build: build) }
    if let cached, cached.userId == account.userId { return cached.capabilities }
    return await load(account)
  }

  @discardableResult public func refresh() async -> ServerCapabilities {
    guard let account = await account() else { return ServerCapabilities(build: build) }
    if let loading, loading.userId == account.userId { return await loading.task.value }
    return await load(account)
  }

  private func load(_ account: Account) async -> ServerCapabilities {
    if let loading, loading.userId == account.userId { return await loading.task.value }
    let task = Task { [session, build] in
      await Self.fetch(account, session: session, build: build)
    }
    loading = (account.userId, task)
    let capabilities = await task.value
    if loading?.userId == account.userId { loading = nil }
    cached = (account.userId, capabilities)
    return capabilities
  }

  private static func fetch(_ account: Account, session: URLSession, build: BuildServices) async
    -> ServerCapabilities
  {
    let serverName = ServerCapabilitiesParser.serverName(ofUserId: account.userId) ?? ""
    let wellKnown = await body(
      of: URL(string: "https://\(serverName)/.well-known/matrix/client"), session: session)
    let versions = await body(
      of: account.homeserver?.appending(path: "_matrix/client/versions"), session: session)
    return ServerCapabilitiesParser.capabilities(
      wellKnown: wellKnown, versions: versions, serverName: serverName,
      homeserver: account.homeserver, build: build)
  }

  private static func body(of url: URL?, session: URLSession) async -> Data? {
    guard let url, url.host() != nil,
      case (let data, let response)? = try? await session.data(from: url),
      (response as? HTTPURLResponse)?.statusCode == 200
    else { return nil }
    return data
  }
}
