import Domain
import Foundation
import Testing

@testable import MatrixData

/// ToM's `/_twake/recoveryWords` through a stubbed URL session (ADR 0024); nothing leaves the machine.
@Suite(.serialized)
struct TomRecoveryWordsTests {
  final class Stub: URLProtocol {
    /// Answers by "METHOD path".
    nonisolated(unsafe) static var responses: [String: (Int, String)] = [:]
    typealias Request = (method: String, authorization: String?, body: String?)
    nonisolated(unsafe) static var requests: [Request] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
      let method = request.httpMethod ?? "GET"
      Self.requests.append(
        (method, request.value(forHTTPHeaderField: "Authorization"), Self.body(of: request)))
      let (status, body) = Self.responses["\(method) \(request.url?.path ?? "")"] ?? (500, "{}")
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data(body.utf8))
      client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    /// A URL session hands a body to a protocol as a stream.
    private static func body(of request: URLRequest) -> String? {
      if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
      guard let stream = request.httpBodyStream else { return nil }
      stream.open()
      defer { stream.close() }
      var data = Data()
      var buffer = [UInt8](repeating: 0, count: 1024)
      while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: buffer.count)
        guard read > 0 else { break }
        data.append(buffer, count: read)
      }
      return String(decoding: data, as: UTF8.self)
    }
  }

  private func words() -> TomRecoveryWords {
    Stub.requests = []
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [Stub.self]
    return TomRecoveryWords(
      tom: URL(string: "https://tom.example.org/")!, accessToken: "token",
      session: URLSession(configuration: configuration))
  }

  @Test func readsTheKeptKeyWithTheMatrixToken() async throws {
    Stub.responses = ["GET /_twake/recoveryWords": (200, #"{"words":"EsTc abcd"}"#)]
    let words = words()

    #expect(try await words.fetch() == "EsTc abcd")
    #expect(Stub.requests.first?.authorization == "Bearer token")
  }

  @Test func notFoundMeansNoKey() async throws {
    Stub.responses = [
      "GET /_twake/recoveryWords": (404, #"{"error":"User has no recovery sentence"}"#)
    ]

    #expect(try await words().fetch() == nil)
  }

  @Test func anyOtherAnswerIsNotAnAnswer() async {
    Stub.responses = ["GET /_twake/recoveryWords": (429, "{}")]

    await #expect(throws: RecoveryVaultError.unavailable) { try await words().fetch() }
  }

  @Test func keepsANewKeyAsWords() async {
    Stub.responses = ["POST /_twake/recoveryWords": (201, "{}")]
    let words = words()

    #expect(await words.save("EsTc abcd") == .saved)
    let post = Stub.requests.first
    #expect(post?.method == "POST")
    #expect(post?.body == #"{"words":"EsTc abcd"}"#)
  }

  @Test func conflictMeansAnotherKeyIsKept() async {
    Stub.responses = ["POST /_twake/recoveryWords": (409, "{}")]

    #expect(await words().save("EsTc abcd") == .alreadyKept)
  }

  @Test func failureWithAnotherKeyKeptMeansThatKeyStayed() async {
    Stub.responses = [
      "POST /_twake/recoveryWords": (500, "{}"),
      "GET /_twake/recoveryWords": (200, #"{"words":"other key"}"#),
    ]

    #expect(await words().save("EsTc abcd") == .alreadyKept)
  }

  @Test func failureWithNothingKeptIsAFailure() async {
    Stub.responses = [
      "POST /_twake/recoveryWords": (500, "{}"),
      "GET /_twake/recoveryWords": (404, "{}"),
    ]

    #expect(await words().save("EsTc abcd") == .failed)
  }

  @Test func deleteLetsTheKeyGo() async {
    Stub.responses = ["DELETE /_twake/recoveryWords": (200, "{}")]
    let words = words()

    await words.delete()

    #expect(Stub.requests.map(\.method) == ["DELETE"])
  }
}
