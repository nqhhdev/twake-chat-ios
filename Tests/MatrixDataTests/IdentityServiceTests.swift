import Domain
import Foundation
import Testing

@testable import MatrixData

final class RecordingTransport: @unchecked Sendable {
  private let lock = NSLock()
  private var _requests: [URLRequest] = []
  private var _answers: [(Int, String)]

  init(_ answers: [(Int, String)]) {
    _answers = answers
  }

  var requests: [URLRequest] { lock.withLock { _requests } }

  func body(_ index: Int) -> [String: Any]? {
    guard let data = requests[index].httpBody else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }

  var transport: IdentityService.Transport {
    { request in
      self.lock.withLock {
        self._requests.append(request)
        guard !self._answers.isEmpty else { return nil }
        let (status, json) = self._answers.removeFirst()
        return (status, Data(json.utf8))
      }
    }
  }
}

struct IdentityServiceTests {
  private let base = URL(string: "https://id.example.org")!

  @Test func hashesFollowTheSpecExample() {
    let alice = ContactAddress.email("alice@example.com")!
    #expect(
      IdentityService.hash(alice, pepper: "matrixrocks")
        == "4kenr7N9drpCJ4AfalmlGQVsOn3o2RHjkADUpXJWZUc")
    let phone = ContactAddress.phone("+1 800 555 2067", regionCode: nil)!
    #expect(
      IdentityService.hash(phone, pepper: "matrixrocks")
        == "nlo35_T5fzSGZzJApqu8lgIudJvmOQtDaHtr-I4rU7I")
  }

  @Test func onlyAnHttpsServerIsUsed() {
    #expect(
      IdentityService(baseURL: URL(string: "http://id.example.org")!, transport: { _ in nil })
        == nil)
    let service = IdentityService(
      baseURL: URL(string: "https://id.example.org:8443/")!, transport: { _ in nil })
    #expect(service?.idServer == "id.example.org:8443")
    #expect(IdentityService(baseURL: base, transport: { _ in nil })?.idServer == "id.example.org")
  }

  @Test func registeringSendsTheOpenIdTokenAndKeepsTheServerToken() async throws {
    let recorder = RecordingTransport([(200, #"{"token":"is-token"}"#)])
    let service = try #require(IdentityService(baseURL: base, transport: recorder.transport))
    let openID = Data(
      #"{"access_token":"oid","token_type":"Bearer","matrix_server_name":"example.org","expires_in":3600}"#
        .utf8)
    let token = try await service.register(openID: openID)
    #expect(token == "is-token")
    let request = try #require(recorder.requests.first)
    #expect(request.httpMethod == "POST")
    #expect(
      request.url?.absoluteString == "https://id.example.org/_matrix/identity/v2/account/register")
    #expect(request.httpBody == openID)
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
  }

  @Test func termsArePickedInTheUserLanguage() async throws {
    let json = """
      {"policies":{"privacy_policy":{"version":"1.2",
        "en":{"name":"Privacy Policy","url":"https://id.example.org/privacy-en.html"},
        "fr":{"name":"Politique de confidentialité","url":"https://id.example.org/privacy-fr.html"}},
      "terms_of_service":{"version":"2","de":{"name":"AGB","url":"https://id.example.org/tos-de.html"}}}}
      """
    let recorder = RecordingTransport([(200, json), (200, json)])
    let service = try #require(IdentityService(baseURL: base, transport: recorder.transport))
    let french = try await service.policies(language: "fr")
    #expect(french.map(\.title) == ["Politique de confidentialité", "AGB"])
    let english = try await service.policies(language: "vi")
    #expect(
      english.map(\.url.absoluteString) == [
        "https://id.example.org/privacy-en.html", "https://id.example.org/tos-de.html",
      ])
    #expect(recorder.requests.first?.url?.path() == "/_matrix/identity/v2/terms")
  }

  @Test func acceptingSendsThePolicyUrlsWithTheToken() async throws {
    let recorder = RecordingTransport([(200, "{}")])
    let service = try #require(IdentityService(baseURL: base, transport: recorder.transport))
    try await service.accept([URL(string: "https://id.example.org/tos")!], token: "t")
    #expect(recorder.requests.first?.httpMethod == "POST")
    #expect(recorder.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer t")
    #expect(recorder.body(0)?["user_accepts"] as? [String] == ["https://id.example.org/tos"])
  }

  @Test func aServerWithoutSha256IsNotUsed() async throws {
    let recorder = RecordingTransport([
      (200, #"{"algorithms":["none"],"lookup_pepper":"p"}"#),
      (200, #"{"algorithms":["none","sha256"],"lookup_pepper":"matrixrocks"}"#),
    ])
    let service = try #require(IdentityService(baseURL: base, transport: recorder.transport))
    await #expect(throws: IdentityError.unavailable) { try await service.pepper(token: "t") }
    #expect(try await service.pepper(token: "t") == "matrixrocks")
    #expect(recorder.requests.first?.url?.path() == "/_matrix/identity/v2/hash_details")
  }

  @Test func theLookupSendsOnlyHashes() async throws {
    let alice = ContactAddress.email("alice@example.com")!
    let hash = IdentityService.hash(alice, pepper: "matrixrocks")
    let recorder = RecordingTransport([
      (200, #"{"mappings":{"\#(hash)":"@alice:example.com"}}"#),
      (400, #"{"errcode":"M_INVALID_PEPPER"}"#),
      (403, #"{"errcode":"M_TERMS_NOT_SIGNED"}"#),
      (401, #"{"errcode":"M_UNAUTHORIZED"}"#),
    ])
    let service = try #require(IdentityService(baseURL: base, transport: recorder.transport))
    let answer = try await service.lookup(hashes: [hash], pepper: "matrixrocks", token: "t")
    #expect(answer == .mappings([hash: "@alice:example.com"]))
    let body = try #require(recorder.body(0))
    #expect(body["addresses"] as? [String] == [hash])
    #expect(body["algorithm"] as? String == "sha256")
    #expect(body["pepper"] as? String == "matrixrocks")
    #expect(
      !String(decoding: recorder.requests[0].httpBody ?? Data(), as: UTF8.self).contains("alice"))
    #expect(try await service.lookup(hashes: [hash], pepper: "old", token: "t") == .invalidPepper)
    await #expect(throws: IdentityError.termsNotAccepted) {
      try await service.lookup(hashes: [hash], pepper: "p", token: "t")
    }
    await #expect(throws: IdentityError.notSignedIn) {
      try await service.lookup(hashes: [hash], pepper: "p", token: "t")
    }
  }

  @Test func theServerComesFromTheAccountOrTheWellKnown() {
    let wellKnown = Data(
      #"{"m.homeserver":{"base_url":"https://matrix.example.org"},"m.identity_server":{"base_url":"https://id.example.org"}}"#
        .utf8)
    #expect(
      IdentityService.baseURL(fromWellKnown: wellKnown)?.absoluteString == "https://id.example.org")
    #expect(IdentityService.baseURL(fromWellKnown: Data("{}".utf8)) == nil)
    let chosen = IdentityService.baseURL(
      fromAccountData: Data(#"{"base_url":"https://vector.im"}"#.utf8))
    #expect(chosen == .some(URL(string: "https://vector.im")))
    let removed = IdentityService.baseURL(fromAccountData: Data(#"{"base_url":null}"#.utf8))
    #expect(removed == .some(nil))
    #expect(IdentityService.baseURL(fromAccountData: Data("oops".utf8)) == nil)
  }

  @Test func aThirdPartyInviteNamesTheServerItsTokenAndTheAddress() {
    let phone = ContactAddress.phone("+33 6 12 34 56 78", regionCode: nil)!
    #expect(
      IdentityServerProxy.inviteBody(phone, idServer: "id.example.org", token: "t") == [
        "id_server": "id.example.org", "id_access_token": "t", "medium": "msisdn",
        "address": "33612345678",
      ])
    let email = ContactAddress.email("carol@example.org")!
    let body = IdentityServerProxy.directChatBody(email, idServer: "id.example.org", token: "t")
    #expect(body["is_direct"] as? Bool == true)
    #expect(body["preset"] as? String == "trusted_private_chat")
    let invites = body["invite_3pid"] as? [[String: String]]
    #expect(invites?.first?["medium"] == "email")
    #expect(invites?.first?["address"] == "carol@example.org")
    let state = body["initial_state"] as? [[String: Any]]
    #expect(state?.first?["type"] as? String == "m.room.encryption")
  }
}
