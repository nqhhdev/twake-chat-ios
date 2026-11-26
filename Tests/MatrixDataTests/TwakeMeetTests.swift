import Foundation
import Testing

@testable import MatrixData

/// The Meet server and ToM's Meet rooms, through a stubbed URL session; nothing leaves the machine (#92).
@Suite(.serialized)
struct TwakeMeetTests {
  final class Stub: URLProtocol {
    nonisolated(unsafe) static var responses: [String: (Int, String)] = [:]
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
      Self.lastRequest = request
      let (status, body) = Self.responses[request.url?.path ?? ""] ?? (404, "{}")
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data(body.utf8))
      client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
  }

  private func meet() -> TwakeMeet {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [Stub.self]
    return TwakeMeet(session: URLSession(configuration: configuration))
  }

  @Test func tomMakesARoomWithTheAccessToken() async {
    Stub.responses = [
      "/_twake/v1/video_call/rooms": (200, #"{"url":"https://meet.example.org/abc-defg-hij"}"#)
    ]
    let room = await meet().createRoom(
      tom: URL(string: "https://tom.example.org")!, accessToken: "token")
    #expect(room == .created(URL(string: "https://meet.example.org/abc-defg-hij")!))
    #expect(Stub.lastRequest?.httpMethod == "POST")
    #expect(Stub.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer token")
  }

  @Test func tomWithoutMeetRoomsLetsTheAppPickTheSlug() async {
    let tom = URL(string: "https://tom.example.org")!
    Stub.responses = ["/_twake/v1/video_call/rooms": (404, "{}")]
    #expect(await meet().createRoom(tom: tom, accessToken: "token") == .unavailable)
    Stub.responses = ["/_twake/v1/video_call/rooms": (422, "{}")]
    #expect(await meet().createRoom(tom: tom, accessToken: "token") == .unavailable)
  }

  @Test func anyOtherAnswerFails() async {
    let tom = URL(string: "https://tom.example.org")!
    Stub.responses = ["/_twake/v1/video_call/rooms": (500, "{}")]
    #expect(await meet().createRoom(tom: tom, accessToken: "token") == .failed)
    Stub.responses = ["/_twake/v1/video_call/rooms": (200, "{}")]
    #expect(await meet().createRoom(tom: tom, accessToken: "token") == .failed)
  }
}
