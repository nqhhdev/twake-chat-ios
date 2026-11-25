import Domain
import Foundation
import Testing

@testable import MatrixData

/// Linking and unlinking e-mails and phones (`/account/3pid/…`): how the server's answers are read.
struct AccountSettingsProxyTests {
  private let base = URL(string: "https://matrix.example.org/_matrix/client/v3/")

  @Test func aLinkedAddressAnswersNothingMore() throws {
    let challenge = try AccountSettingsProxy.linkAnswer(
      status: 200, data: Data("{}".utf8), homeserver: base)
    #expect(challenge == nil)
  }

  @Test func theServerAskingForConfirmationGivesItsChallenge() throws {
    let json = Data(#"{"session":"s1","flows":[{"stages":["m.login.sso"]}]}"#.utf8)
    let challenge = try #require(
      try AccountSettingsProxy.linkAnswer(status: 401, data: json, homeserver: base))
    #expect(challenge.session == "s1")
    #expect(!challenge.acceptsPassword)
    #expect(
      challenge.webURL?.absoluteString
        == "https://matrix.example.org/_matrix/client/v3/auth/m.login.sso/fallback/web?session=s1")
  }

  @Test func anUnopenedLinkAndAnAddressInUseAreToldApart() {
    let notOpened = Data(#"{"errcode":"M_THREEPID_AUTH_FAILED"}"#.utf8)
    let inUse = Data(#"{"errcode":"M_THREEPID_IN_USE"}"#.utf8)
    #expect(throws: SettingsError.addressNotConfirmed) {
      try AccountSettingsProxy.linkAnswer(status: 400, data: notOpened, homeserver: base)
    }
    #expect(throws: SettingsError.addressInUse) {
      try AccountSettingsProxy.linkAnswer(status: 400, data: inUse, homeserver: base)
    }
    #expect(throws: SettingsError.requestFailed) {
      try AccountSettingsProxy.linkAnswer(status: 500, data: Data(), homeserver: base)
    }
  }

  @Test func aPhoneIsRemovedWithoutItsPlus() {
    #expect(
      AccountSettingsProxy.removalBody(LinkedAddress(kind: .phone, address: "+33612345678"))
        == ["medium": "msisdn", "address": "33612345678"])
    #expect(
      AccountSettingsProxy.removalBody(LinkedAddress(kind: .email, address: "a@b.org"))
        == ["medium": "email", "address": "a@b.org"])
  }

  @Test func aPhoneCodeIsRequestedInInternationalForm() {
    let phone = ContactAddress.phone("06 12 34 56 78", regionCode: "FR")!
    let body = AccountSettingsProxy.phoneRequestBody(phone, regionCode: "fr", secret: "s")
    #expect(body["client_secret"] as? String == "s")
    #expect(body["country"] as? String == "FR")
    #expect(body["phone_number"] as? String == "+33612345678")
    #expect(body["send_attempt"] as? Int == 1)
  }

  @Test func theCodeGoesWhereTheServerSays() throws {
    let phone = ContactAddress.phone("+33612345678", regionCode: nil)!
    let answer = Data(
      #"{"sid":"sid1","submit_url":"https://matrix.example.org/_matrix/client/unstable/add_threepid/msisdn/submit_token"}"#
        .utf8)
    let pending = try AccountSettingsProxy.pendingPhone(phone, secret: "s", answer: answer)
    #expect(pending.sessionId == "sid1")
    #expect(pending.phone == "+33612345678")
    #expect(pending.submitURL.path().hasSuffix("/msisdn/submit_token"))
    #expect(
      AccountSettingsProxy.phoneCodeBody(pending, code: " 123456 ")
        == ["client_secret": "s", "sid": "sid1", "token": "123456"])
    #expect(throws: SettingsError.phoneNotSupported) {
      try AccountSettingsProxy.pendingPhone(phone, secret: "s", answer: Data(#"{"sid":"x"}"#.utf8))
    }
  }

  @Test func aWrongCodeIsToldApartFromAFailure() throws {
    try AccountSettingsProxy.phoneCodeAnswer(status: 200, data: Data(#"{"success":true}"#.utf8))
    #expect(throws: SettingsError.wrongCode) {
      try AccountSettingsProxy.phoneCodeAnswer(status: 200, data: Data(#"{"success":false}"#.utf8))
    }
    #expect(throws: SettingsError.wrongCode) {
      try AccountSettingsProxy.phoneCodeAnswer(
        status: 400, data: Data(#"{"errcode":"M_THREEPID_AUTH_FAILED"}"#.utf8))
    }
    #expect(throws: SettingsError.requestFailed) {
      try AccountSettingsProxy.phoneCodeAnswer(status: 502, data: Data())
    }
    #expect(
      AccountSettingsProxy.addressError(
        from: Data(#"{"errcode":"M_THREEPID_MEDIUM_NOT_SUPPORTED"}"#.utf8)) == .phoneNotSupported)
  }
}
