import Foundation
import Testing

@testable import MatrixData

@Suite(.serialized)
struct TwakeContactLookupTests {
  final class Stub: URLProtocol {
    nonisolated(unsafe) static var responses: [String: (Int, String)] = [:]
    nonisolated(unsafe) static var lastAuthorization: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
      Self.lastAuthorization = request.value(forHTTPHeaderField: "Authorization")
      let (status, body) = Self.responses[request.url?.path ?? ""] ?? (404, "{}")
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data(body.utf8))
      client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
  }

  private func lookup() -> TwakeContactLookup {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [Stub.self]
    return TwakeContactLookup(session: URLSession(configuration: configuration))
  }

  @Test func searchesTheToMAddressBook() async throws {
    Stub.responses = [
      "/_twake/identity/v1/lookup/match": (
        200,
        #"{"matches":[{"uid":"alice","displayName":"Alice"},{"uid":"bob","address":"@bob:other.org","cn":"Bob B"}],"inactive_matches":[]}"#
      )
    ]
    let matches = try await lookup().search(
      "al", limit: 10, tom: URL(string: "https://tom.example.org/")!, serverName: "example.org",
      accessToken: "token")
    #expect(
      matches == [
        .init(userId: "@alice:example.org", displayName: "Alice"),
        .init(userId: "@bob:other.org", displayName: "Bob B"),
      ])
    #expect(Stub.lastAuthorization == "Bearer token")
  }
}

extension TwakeContactLookupTests {
  @Test func theCommonSettingsLanguageComesFromUserInfo() async {
    Stub.responses = [
      "/_twake/v1/user_info/@me:example.org": (200, #"{"language":"fr-FR","theme":"dark"}"#)
    ]
    let tom = URL(string: "https://tom.example.org")!
    #expect(
      await lookup().language(of: "@me:example.org", tom: tom, accessToken: "token") == "fr-FR")
    #expect(Stub.lastAuthorization == "Bearer token")
    Stub.responses = ["/_twake/v1/user_info/@me:example.org": (200, #"{"theme":"dark"}"#)]
    #expect(await lookup().language(of: "@me:example.org", tom: tom, accessToken: "token") == nil)
    Stub.responses = [:]
    #expect(await lookup().language(of: "@me:example.org", tom: tom, accessToken: "token") == nil)
  }
}
