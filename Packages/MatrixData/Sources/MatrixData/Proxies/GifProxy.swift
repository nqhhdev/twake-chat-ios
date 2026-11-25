import Domain
import Foundation

public actor GifProxy: GifRepository {
  struct OpenIDToken: Sendable, Equatable {
    let accessToken: String
    let serverName: String
    let expiresIn: TimeInterval
  }

  static let pageSize = 24
  static let tokenMargin: TimeInterval = 60

  private let baseURL: URL
  private let session: URLSession
  private let requestToken: @Sendable () async -> OpenIDToken?
  private let retryDelay: Duration
  private var token: (value: OpenIDToken, expiresAt: Date)?
  private var placeholder: String?

  public init(baseURL: URL, authentication: MatrixAuthenticationRepository) {
    self.init(baseURL: baseURL, session: .shared, retryDelay: .seconds(2)) {
      await Self.openIDToken(client: await authentication.clientProxy)
    }
  }

  init(
    baseURL: URL, session: URLSession, retryDelay: Duration,
    requestToken: @escaping @Sendable () async -> OpenIDToken?
  ) {
    let text = baseURL.absoluteString
    self.baseURL = text.hasSuffix("/") ? URL(string: String(text.dropLast())) ?? baseURL : baseURL
    self.session = session
    self.retryDelay = retryDelay
    self.requestToken = requestToken
  }

  public func searchPlaceholder() async -> String? {
    if let placeholder { return placeholder }
    guard let data = await get("/v1/modules", query: []) else { return nil }
    placeholder = GifPageMapper.placeholder(data)
    return placeholder
  }

  public func trending(cursor: String?, locale: String) async -> GifPage? {
    await page("/v1/gif/trending", query: [], cursor: cursor, locale: locale)
  }

  public func search(_ query: String, cursor: String?, locale: String) async -> GifPage? {
    await page(
      "/v1/gif/search", query: [URLQueryItem(name: "q", value: query)], cursor: cursor,
      locale: locale)
  }

  public func download(_ gif: Gif) async throws(GifError) -> GifFile {
    guard let (data, response) = try? await session.data(from: gif.url),
      let http = response as? HTTPURLResponse
    else { throw .downloadFailed }
    if http.statusCode == 403 { throw .expired }
    guard http.statusCode == 200 else { throw .downloadFailed }
    let type =
      http.value(forHTTPHeaderField: "Content-Type")?
      .split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    let mimeType = type.hasPrefix("image/") ? type : "image/gif"
    let title = gif.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let name =
      (title.isEmpty ? "GIF" : title).replacingOccurrences(of: "/", with: "-") + "."
      + GifPageMapper.fileExtension(for: mimeType)
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "gif-\(UUID().uuidString)", directoryHint: .isDirectory)
    let fileURL = directory.appending(path: name)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try data.write(to: fileURL)
    } catch {
      throw .downloadFailed
    }
    return GifFile(fileURL: fileURL, mimeType: mimeType, size: data.count)
  }

  private func page(_ path: String, query: [URLQueryItem], cursor: String?, locale: String) async
    -> GifPage?
  {
    var items = [URLQueryItem(name: "limit", value: String(Self.pageSize))] + query
    if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
    items.append(URLQueryItem(name: "locale", value: locale))
    guard let data = await get(path, query: items) else { return nil }
    return GifPageMapper.page(data, baseURL: baseURL)
  }

  private func get(_ path: String, query: [URLQueryItem]) async -> Data? {
    guard var components = URLComponents(string: baseURL.absoluteString + path) else { return nil }
    if !query.isEmpty { components.queryItems = query }
    guard let url = components.url else { return nil }
    for isRetry in [false, true] {
      guard let token = await currentToken() else { return nil }
      var request = URLRequest(url: url)
      request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
      request.setValue(token.serverName, forHTTPHeaderField: "X-Matrix-Server-Name")
      guard let (data, response) = try? await session.data(for: request),
        let status = (response as? HTTPURLResponse)?.statusCode
      else { return nil }
      if !isRetry, status == 401 {
        self.token = nil
        continue
      }
      if !isRetry, status == 429 {
        try? await Task.sleep(for: retryDelay)
        continue
      }
      return status == 200 ? data : nil
    }
    return nil
  }

  private func currentToken() async -> OpenIDToken? {
    if let token, Date.now < token.expiresAt { return token.value }
    guard let fresh = await requestToken() else { return nil }
    token = (fresh, Date.now.addingTimeInterval(fresh.expiresIn - Self.tokenMargin))
    return fresh
  }

  static func openIDToken(client: ClientProxy?) async -> OpenIDToken? {
    guard let client = client?.client, let userId = try? client.userId(),
      let request = ClientServerRequest.make(
        client: client, path: "user/\(ClientServerRequest.encode(userId))/openid/request_token",
        method: "POST", json: [:]),
      let object = await ClientServerRequest.object(request)
    else { return nil }
    return token(from: object)
  }

  static func token(from object: [String: Any]) -> OpenIDToken? {
    guard let accessToken = object["access_token"] as? String,
      let serverName = object["matrix_server_name"] as? String
    else { return nil }
    let expiresIn = (object["expires_in"] as? NSNumber)?.doubleValue ?? 3600
    return OpenIDToken(accessToken: accessToken, serverName: serverName, expiresIn: expiresIn)
  }
}
