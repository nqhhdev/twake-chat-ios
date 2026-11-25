import Domain
import Foundation
import Testing

@testable import MatrixData

@Suite(.serialized)
struct GifProxyTests {
  final class Stub: URLProtocol {
    nonisolated(unsafe) static var responses: [String: [(Int, String, String)]] = [:]
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
      Self.requests.append(request)
      let path = request.url?.path ?? ""
      var queue = Self.responses[path] ?? []
      let (status, type, body) =
        queue.isEmpty ? (404, "application/json", "{}") : queue.removeFirst()
      Self.responses[path] = queue
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil,
        headerFields: ["Content-Type": type])!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data(body.utf8))
      client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
  }

  final class Tokens: @unchecked Sendable {
    var count = 0
  }

  private let base = URL(string: "https://proxy.example/")!

  private func proxy(tokens: Tokens = Tokens()) -> GifProxy {
    Stub.requests = []
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [Stub.self]
    return GifProxy(
      baseURL: base, session: URLSession(configuration: configuration), retryDelay: .zero
    ) {
      tokens.count += 1
      return GifProxy.OpenIDToken(
        accessToken: "openid-\(tokens.count)", serverName: "example.org", expiresIn: 3600)
    }
  }

  private static let page = """
    {"results":[
      {"id":"a","title":"Cat","media":[
        {"size":"md","format":"gif","url":"/m/a-md.gif","width":480,"height":360,"bytes":2000},
        {"size":"sm","format":"gif","url":"https://proxy.example/m/a-sm.gif","width":220,"height":165,"bytes":600},
        {"size":"sm","format":"webp","url":"/m/a-sm.webp","width":300,"height":225,"bytes":300},
        {"size":"hd","format":"webp","url":"/m/a-hd.webp","width":640,"height":480,"bytes":900}]},
      {"id":"b","media":[{"size":"sm","format":"gif","url":"https://klipy.example/b.gif"}]},
      {"id":"c","media":[{"size":"xs","format":"jpg","url":"/m/c.jpg"},{"size":"md","format":"webp","url":"/m/c.webp"}]}
    ],"next":"cursor-2"}
    """

  @Test func aPageKeepsOnlyTheProxysMediaAndPrefersTheSmallGif() throws {
    let page = try #require(GifPageMapper.page(Data(Self.page.utf8), baseURL: base))
    #expect(page.next == "cursor-2")
    #expect(page.results.map(\.id) == ["a", "c"])
    let cat = page.results[0]
    #expect(cat.title == "Cat")
    #expect(cat.url.absoluteString == "https://proxy.example/m/a-sm.gif")
    #expect(cat.width == 220)
    #expect(cat.height == 165)
    #expect(cat.previewURL.absoluteString == "https://proxy.example/m/a-sm.webp")
    #expect(page.results[1].url.absoluteString == "https://proxy.example/m/c.webp")
    #expect(page.results[1].previewURL.absoluteString == "https://proxy.example/m/c.webp")
  }

  @Test func thePlaceholderComesFromTheGifModule() {
    let placeholder = #"{"modules":{"gif":{"attribution":{"searchPlaceholder":"Search KLIPY"}}}}"#
    #expect(GifPageMapper.placeholder(Data(placeholder.utf8)) == "Search KLIPY")
    let named = #"{"modules":{"gif":{"attribution":{"name":"KLIPY"}}}}"#
    #expect(GifPageMapper.placeholder(Data(named.utf8)) == "Search KLIPY")
    #expect(GifPageMapper.placeholder(Data(#"{"modules":{}}"#.utf8)) == nil)
  }

  @Test func requestsCarryTheOpenIdTokenAndServerNameAndRetryOnceAfterA401() async throws {
    Stub.responses = [
      "/v1/gif/search": [(401, "application/json", "{}"), (200, "application/json", Self.page)]
    ]
    let tokens = Tokens()
    let proxy = proxy(tokens: tokens)
    let page = await proxy.search("cat", cursor: "c1", locale: "fr")
    #expect(page?.results.count == 2)
    #expect(tokens.count == 2)
    let last = try #require(Stub.requests.last)
    #expect(last.value(forHTTPHeaderField: "Authorization") == "Bearer openid-2")
    #expect(last.value(forHTTPHeaderField: "X-Matrix-Server-Name") == "example.org")
    let query = URLComponents(url: last.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(query.contains(URLQueryItem(name: "q", value: "cat")))
    #expect(query.contains(URLQueryItem(name: "cursor", value: "c1")))
    #expect(query.contains(URLQueryItem(name: "locale", value: "fr")))
    #expect(query.contains(URLQueryItem(name: "limit", value: "24")))
  }

  @Test func aTooManyRequestsAnswerIsTriedOnceMore() async {
    Stub.responses = [
      "/v1/gif/trending": [(429, "application/json", "{}"), (200, "application/json", Self.page)]
    ]
    let proxy = proxy()
    #expect(await proxy.trending(cursor: nil, locale: "en")?.results.count == 2)
    #expect(Stub.requests.count == 2)
  }

  @Test func theTokenIsKeptBetweenRequestsAndThePlaceholderAskedOnce() async {
    Stub.responses = [
      "/v1/modules": [
        (200, "application/json", #"{"modules":{"gif":{"attribution":{"name":"KLIPY"}}}}"#)
      ],
      "/v1/gif/trending": [(200, "application/json", Self.page)],
    ]
    let tokens = Tokens()
    let proxy = proxy(tokens: tokens)
    #expect(await proxy.searchPlaceholder() == "Search KLIPY")
    #expect(await proxy.searchPlaceholder() == "Search KLIPY")
    _ = await proxy.trending(cursor: nil, locale: "en")
    #expect(tokens.count == 1)
    #expect(Stub.requests.count == 2)
  }

  @Test func aDownloadedGifIsWrittenUnderItsTitleAndAnExpiredLinkSaysSo() async throws {
    Stub.responses = [
      "/m/a.gif": [(200, "image/gif", "GIF89a")],
      "/m/old.gif": [(403, "text/plain", "")],
    ]
    let proxy = proxy()
    let gif = Gif(
      id: "a", title: " Happy/cat ", previewURL: base,
      url: URL(string: "https://proxy.example/m/a.gif")!,
      width: 1, height: 1)
    let file = try await proxy.download(gif)
    #expect(file.fileURL.lastPathComponent == "Happy-cat.gif")
    #expect(file.mimeType == "image/gif")
    #expect(file.size == 6)
    try? FileManager.default.removeItem(at: file.fileURL.deletingLastPathComponent())
    let old = Gif(
      id: "o", title: "", previewURL: base, url: URL(string: "https://proxy.example/m/old.gif")!,
      width: 1, height: 1)
    await #expect(throws: GifError.expired) { try await proxy.download(old) }
  }

  @Test func theOpenIdAnswerIsRead() {
    let token = GifProxy.token(from: [
      "access_token": "t", "matrix_server_name": "example.org", "expires_in": 3600,
      "token_type": "Bearer",
    ])
    #expect(
      token == GifProxy.OpenIDToken(accessToken: "t", serverName: "example.org", expiresIn: 3600))
    #expect(GifProxy.token(from: ["access_token": "t"]) == nil)
  }

  @Test func onlyAnOwnersExplicitOffTurnsGifsOff() {
    #expect(TimelineProxy.gifsEnabled(["enabled": false]) == false)
    #expect(TimelineProxy.gifsEnabled(["enabled": true]))
    #expect(TimelineProxy.gifsEnabled([:]))
  }
}
