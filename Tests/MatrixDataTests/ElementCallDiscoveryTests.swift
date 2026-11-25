import Domain
import Foundation
import Testing

@testable import MatrixData

@Suite(.serialized)
struct ElementCallDiscoveryTests {
  final class Stub: URLProtocol {
    nonisolated(unsafe) static var responses: [String: (Int, String)] = [:]
    nonisolated(unsafe) static var hosts: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
      Self.hosts.append(request.url?.host() ?? "")
      let (status, body) = Self.responses[request.url?.path ?? ""] ?? (404, "{}")
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data(body.utf8))
      client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
  }

  private func discovery() -> ElementCallDiscovery {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [Stub.self]
    return ElementCallDiscovery(session: URLSession(configuration: configuration))
  }

  private static let clientPath = "/.well-known/matrix/client"
  private static let elementPath = "/.well-known/element/element.json"

  @Test func aLiveKitTokenServiceMakesCallsAvailable() async throws {
    Stub.hosts = []
    Stub.responses = [
      Self.clientPath: (
        200,
        #"{"org.matrix.msc4143.rtc_foci":[{"type":"livekit","livekit_base_url":"https://meet.example.org","livekit_service_url":"https://rtc.example.org"}]}"#
      )
    ]
    let services = try #require(await discovery().services(forUserId: "@me:example.org"))
    #expect(services.livekitService?.absoluteString == "https://rtc.example.org")
    #expect(services.widgetURL == nil)
    #expect(Set(Stub.hosts) == ["example.org"])
  }

  @Test func aMeetBaseURLAloneIsNoTokenService() async throws {
    Stub.responses = [
      Self.clientPath: (
        200,
        #"{"org.matrix.msc4143.rtc_foci":[{"type":"livekit","livekit_base_url":"https://meet.example.org/"}]}"#
      )
    ]
    let services = try #require(await discovery().services(forUserId: "@me:example.org"))
    #expect(services.livekitService == nil)
  }

  @Test func otherFociAndInsecureURLsAreIgnored() async throws {
    Stub.responses = [
      Self.clientPath: (
        200,
        #"{"org.matrix.msc4143.rtc_foci":[{"type":"other","livekit_service_url":"https://a.example.org"},{"type":"livekit","livekit_service_url":"http://b.example.org"},{"type":"livekit","livekit_service_url":"https://c.example.org"}]}"#
      )
    ]
    let services = try #require(await discovery().services(forUserId: "@me:example.org"))
    #expect(services.livekitService?.absoluteString == "https://c.example.org")
  }

  @Test func theElementWellKnownNamesTheCallApp() async throws {
    Stub.responses = [
      Self.clientPath: (
        200,
        #"{"org.matrix.msc4143.rtc_foci":[{"type":"livekit","livekit_service_url":"https://rtc.example.org"}]}"#
      ),
      Self.elementPath: (200, #"{"call":{"widget_url":"https://call.example.org/"}}"#),
    ]
    let services = try #require(await discovery().services(forUserId: "@me:example.org"))
    #expect(services.widgetURL?.absoluteString == "https://call.example.org/")
  }

  @Test func aMalformedFociListLeavesNoService() async throws {
    Stub.responses = [Self.clientPath: (200, #"{"org.matrix.msc4143.rtc_foci":"livekit"}"#)]
    let services = try #require(await discovery().services(forUserId: "@me:example.org"))
    #expect(services.livekitService == nil)
  }

  @Test func noWellKnownMeansNoServices() async {
    Stub.responses = [:]
    #expect(await discovery().services(forUserId: "@me:example.org") == nil)
    #expect(await discovery().services(forUserId: "nobody") == nil)
  }

  @Test func theWidgetIntentFollowsTheRoomKind() {
    #expect(ElementCallProxy.widgetIntent(.start, isDirect: false) == .startCall)
    #expect(ElementCallProxy.widgetIntent(.join, isDirect: false) == .joinExisting)
    #expect(ElementCallProxy.widgetIntent(.start, isDirect: true) == .startCallDm)
    #expect(ElementCallProxy.widgetIntent(.join, isDirect: true) == .joinExistingDm)
  }
}
