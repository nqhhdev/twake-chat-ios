import Domain
import Foundation
import Testing

@testable import MatrixData

@Suite(.serialized)
struct ServerCapabilitiesProxyTests {
  final class Stub: URLProtocol {
    nonisolated(unsafe) static var responses: [String: (Int, String)] = [:]
    nonisolated(unsafe) static var requests: [URL] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
      Self.requests.append(request.url!)
      let key = (request.url?.host() ?? "") + (request.url?.path ?? "")
      let (status, body) = Self.responses[key] ?? (404, "{}")
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data(body.utf8))
      client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
  }

  final class Accounts: @unchecked Sendable {
    var userId: String? = "@me:example.org"
  }

  private func makeProxy(_ accounts: Accounts, build: BuildServices = BuildServices())
    -> ServerCapabilitiesProxy
  {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [Stub.self]
    return ServerCapabilitiesProxy(
      account: {
        accounts.userId.map {
          .init(userId: $0, homeserver: URL(string: "https://matrix.example.org"))
        }
      },
      session: URLSession(configuration: configuration), build: build)
  }

  private static let twakeWellKnown = #"""
    {"m.homeserver":{"base_url":"https://matrix.example.org"},
     "m.identity_server":{"base_url":"https://id.example.org"},
     "t.server":{"base_url":"https://tom.example.org/","server_name":"example.org"},
     "org.matrix.msc4143.rtc_foci":[{"type":"other","livekit_base_url":"https://x.example.org"},
       {"type":"livekit","livekit_base_url":"https://meet.example.org/"}],
     "app.twake.chat":{"support_contact":"@support:example.org","enable_invitations":true,
       "common_settings":{"enabled":true,"application_url":"https://settings.example.org/{username}"},
       "side_service":{"base_url":"https://side.example.org"},"web_url":"https://chat.example.org"}}
    """#

  @Test func readsTheWellKnownVersionsAndBuild() async throws {
    Stub.requests = []
    Stub.responses = [
      "example.org/.well-known/matrix/client": (200, Self.twakeWellKnown),
      "matrix.example.org/_matrix/client/versions": (
        200,
        #"{"versions":["v1.11"],"unstable_features":{"org.matrix.msc4140":true,"org.matrix.msc3266":false}}"#
      ),
    ]
    let build = BuildServices(supportURL: URL(string: "https://help.example.org"))
    let capabilities = await makeProxy(Accounts(), build: build).current()
    #expect(capabilities.homeserver?.absoluteString == "https://matrix.example.org")
    #expect(capabilities.identityServer?.absoluteString == "https://id.example.org")
    #expect(capabilities.tom?.baseURL.absoluteString == "https://tom.example.org/")
    #expect(capabilities.tom?.serverName == "example.org")
    #expect(capabilities.callFoci.map(\.absoluteString) == ["https://meet.example.org/"])
    #expect(capabilities.supportContact == "@support:example.org")
    #expect(capabilities.twakeChat.invitationsEnabled)
    #expect(capabilities.twakeChat.sideService?.absoluteString == "https://side.example.org")
    #expect(capabilities.twakeChat.webURL?.absoluteString == "https://chat.example.org")
    #expect(
      capabilities.commonSettingsPage(for: "@me:example.org")?.absoluteString
        == "https://settings.example.org/me")
    #expect(capabilities.unstableFeatures == ["org.matrix.msc4140"])
    #expect(capabilities.build == build)
    #expect(MeetCallProxy.meetBase(of: capabilities)?.absoluteString == "https://meet.example.org")
  }

  @Test func aPlainSynapseAnnouncesNoTwakeService() async {
    Stub.responses = [
      "example.org/.well-known/matrix/client": (
        200, #"{"m.homeserver":{"base_url":"https://matrix.example.org"}}"#
      )
    ]
    let capabilities = await makeProxy(Accounts()).current()
    #expect(capabilities.tom == nil)
    #expect(capabilities.callFoci.isEmpty)
    #expect(capabilities.twakeChat == ServerCapabilities.TwakeChat())
    #expect(capabilities.unstableFeatures.isEmpty)
  }

  @Test func theNewToMKeyWinsAndTheServerNameDefaultsToTheUsers() async {
    Stub.responses = [
      "example.org/.well-known/matrix/client": (
        200,
        #"{"app.twake.tom":{"base_url":"https://new.example.org"},"t.server":{"base_url":"https://old.example.org"}}"#
      )
    ]
    let capabilities = await makeProxy(Accounts()).current()
    #expect(
      capabilities.tom
        == .init(baseURL: URL(string: "https://new.example.org")!, serverName: "example.org"))
  }

  @Test func invitationsAreOffUnlessTheWellKnownTurnsThemOn() async {
    Stub.responses = [
      "example.org/.well-known/matrix/client": (
        200, #"{"t.server":{"base_url":"https://tom.example.org"},"app.twake.chat":"weird"}"#
      )
    ]
    let capabilities = await makeProxy(Accounts()).current()
    #expect(!capabilities.twakeChat.invitationsEnabled)
    #expect(capabilities.tom?.serverName == "example.org")
  }

  @Test func disabledCommonSettingsAndMalformedEntriesAreIgnored() async {
    Stub.responses = [
      "example.org/.well-known/matrix/client": (
        200,
        #"{"org.matrix.msc4143.rtc_foci":"nope","app.twake.chat":{"common_settings":{"enabled":false,"application_url":"https://s.example.org/{username}"},"support_contact":42}}"#
      )
    ]
    let capabilities = await makeProxy(Accounts()).current()
    #expect(capabilities.callFoci.isEmpty)
    #expect(capabilities.twakeChat.commonSettingsURL == nil)
    #expect(capabilities.supportContact == nil)
  }

  @Test func theAnswerIsKeptPerAccountUntilRefreshed() async {
    Stub.requests = []
    Stub.responses = [
      "example.org/.well-known/matrix/client": (
        200, #"{"t.server":{"base_url":"https://tom.example.org"}}"#
      ),
      "other.org/.well-known/matrix/client": (200, "{}"),
    ]
    let accounts = Accounts()
    let proxy = makeProxy(accounts)
    _ = await proxy.current()
    _ = await proxy.current()
    #expect(Stub.requests.filter { $0.path == "/.well-known/matrix/client" }.count == 1)
    await proxy.refresh()
    #expect(Stub.requests.filter { $0.path == "/.well-known/matrix/client" }.count == 2)
    accounts.userId = "@me:other.org"
    #expect(await proxy.current().tom == nil)
  }

  @Test func signedOutThereIsOnlyTheBuild() async {
    Stub.requests = []
    let accounts = Accounts()
    accounts.userId = nil
    let build = BuildServices(supportURL: URL(string: "https://help.example.org"))
    #expect(await makeProxy(accounts, build: build).current() == ServerCapabilities(build: build))
    #expect(Stub.requests.isEmpty)
  }
}
