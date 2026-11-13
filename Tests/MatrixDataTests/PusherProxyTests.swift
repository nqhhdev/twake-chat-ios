import Foundation
import Testing

@testable import MatrixData

/// The pusher matches the Flutter app's, so the Twake gateway's APNs set-up serves the iOS app (ADR 0012).
struct PusherProxyTests {
  @Test func theTokenIsSentInBase64ToTheSandboxAppInDebug() {
    let token = Data([0x01, 0x02, 0xFE, 0xFF])
    let debug = PusherProxy.identifiers(token: token, isProduction: false)
    #expect(debug.pushkey == "AQL+/w==")
    #expect(debug.appId == "app.twake.ios.chat.sandbox")
    #expect(PusherProxy.identifiers(token: token, isProduction: true).appId == "app.twake.ios.chat")
  }

  @Test func thePayloadAsksForAMutableAlertAndNamesTheAccount() throws {
    let json = PusherProxy.defaultPayload(clientIdentifier: "abc")
    let object = try #require(
      try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let aps = try #require(object["aps"] as? [String: Any])
    #expect(aps["mutable-content"] as? Int == 1)
    #expect((aps["alert"] as? [String: Any])?["loc-key"] as? String == "newMessageInTwake")
    #expect(object["pusher_notification_client_identifier"] as? String == "abc")
  }

  @Test func theAccountIsNamedByAHashNotItsId() {
    let id = PusherProxy.clientIdentifier("@alice:example.org")
    #expect(id.count == 64)
    #expect(!id.contains("alice"))
  }
}
