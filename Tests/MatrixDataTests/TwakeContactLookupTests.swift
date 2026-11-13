import Foundation
import Testing

@testable import MatrixData

/// The ToM lookup reads `t.server` and the address book through a stubbed URL session; nothing leaves the machine.
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
      let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
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

  @Test func findsTheToMServerAndSearchesItsAddressBook() async throws {
    Stub.responses = [
      "/.well-known/matrix/client": (
        200, #"{"t.server":{"base_url":"https://tom.example.org/","server_name":"example.org"}}"#
      ),
      "/_twake/identity/v1/lookup/match": (
        200,
        #"{"matches":[{"uid":"alice","displayName":"Alice"},{"uid":"bob","address":"@bob:other.org","cn":"Bob B"}],"inactive_matches":[]}"#
      ),
    ]
    let lookup = lookup()
    let tom = try #require(await lookup.tomServer(forUserId: "@me:example.org"))
    #expect(tom.baseURL.absoluteString == "https://tom.example.org/")
    let matches = try await lookup.search(
      "al", limit: 10, tom: tom.baseURL, serverName: tom.serverName, accessToken: "token")
    #expect(matches == [.init(userId: "@alice:example.org", displayName: "Alice"), .init(userId: "@bob:other.org", displayName: "Bob B")])
    #expect(Stub.lastAuthorization == "Bearer token")
  }

  @Test func aServerWithoutToMHasNoAddressBook() async {
    Stub.responses = ["/.well-known/matrix/client": (200, #"{"m.homeserver":{"base_url":"https://m.example.org"}}"#)]
    #expect(await lookup().tomServer(forUserId: "@me:example.org") == nil)
  }
}
