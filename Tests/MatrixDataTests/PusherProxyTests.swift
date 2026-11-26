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

  @Test func thePusherKeepsThePushersOfOtherAccountsOnTheSameDevice() throws {
    let body = PusherProxy.pusherBody(
      pushkey: "key", appId: "app.twake.ios.chat", gatewayURL: "https://push.example/notify",
      deviceName: "Twake Chat on iPhone", clientIdentifier: "abc")
    #expect(body["append"] as? Bool == true)
    #expect(body["kind"] as? String == "http")
    #expect(body["pushkey"] as? String == "key")
    #expect(body["app_id"] as? String == "app.twake.ios.chat")
    #expect(body["app_display_name"] as? String == "Twake Chat")
    #expect(body["device_display_name"] as? String == "Twake Chat on iPhone")
    #expect(body["lang"] as? String == "en")
    let data = try #require(body["data"] as? [String: Any])
    #expect(data["url"] as? String == "https://push.example/notify")
    #expect(data["format"] as? String == "event_id_only")
    let payload = try #require(data["default_payload"] as? [String: Any])
    #expect(payload["pusher_notification_client_identifier"] as? String == "abc")
    #expect((payload["aps"] as? [String: Any])?["mutable-content"] as? Int == 1)
  }
}
