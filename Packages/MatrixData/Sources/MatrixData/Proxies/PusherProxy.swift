import CryptoKit
import Domain
import Foundation
import MatrixRustSDK

/// `PushRepository` on the SDK client (ADR 0006): an HTTP pusher to the Twake push gateway, the same one the Flutter
/// app registers (`app_config.dart`, `background_push.dart`), so the existing APNs set-up for the bundle identifier
/// serves both apps (ADR 0012). Nothing here logs: the token identifies the device.
public actor PusherProxy: PushRepository {
  static let productionAppId = "app.twake.ios.chat"
  static let sandboxAppId = "app.twake.ios.chat.sandbox"

  private let clientProxy: @Sendable () async -> ClientProxy?
  private let deviceName: String
  private let gatewayURL: String
  private var registered: PusherIdentifiers?

  /// - Parameters:
  ///   - gatewayURL: The push gateway's notify URL, from build configuration (ADR 0009).
  ///   - deviceName: How the device is named in the account's sessions, such as "Twake Chat on iPhone".
  public init(
    authentication: MatrixAuthenticationRepository, gatewayURL: String, deviceName: String
  ) {
    clientProxy = { await authentication.clientProxy }
    self.gatewayURL = gatewayURL
    self.deviceName = deviceName
  }

  public func register(deviceToken: Data, isProduction: Bool) async throws(PushError) {
    guard let client = await clientProxy() else { throw .notSignedIn }
    let identifiers = Self.identifiers(token: deviceToken, isProduction: isProduction)
    let userId = (try? client.userId) ?? ""
    do {
      try await client.client.setPusher(
        identifiers: PusherIdentifiers(pushkey: identifiers.pushkey, appId: identifiers.appId),
        kind: .http(
          data: HttpPusherData(
            url: gatewayURL, format: .eventIdOnly,
            defaultPayload: Self.defaultPayload(clientIdentifier: Self.clientIdentifier(userId)))),
        appDisplayName: "Twake Chat", deviceDisplayName: deviceName, profileTag: nil, lang: "en")
      registered = PusherIdentifiers(pushkey: identifiers.pushkey, appId: identifiers.appId)
    } catch {
      throw .requestFailed
    }
  }

  public func unregister() async {
    guard let registered, let client = await clientProxy() else { return }
    try? await client.client.deletePusher(identifiers: registered)
    self.registered = nil
  }

  /// The pushkey is the APNs token in base64, as Sygnal's APNs pushkin expects and the Flutter app sends; Debug builds
  /// use the sandbox app.
  static func identifiers(token: Data, isProduction: Bool) -> (pushkey: String, appId: String) {
    (token.base64EncodedString(), isProduction ? productionAppId : sandboxAppId)
  }

  /// The payload the gateway sends: a mutable alert, so a notification service extension can replace it with the
  /// decrypted message, and the account the push is for.
  static func defaultPayload(clientIdentifier: String) -> String {
    let payload: [String: Any] = [
      "aps": [
        "mutable-content": 1, "content-available": 1, "badge": 1, "sound": "default",
        "alert": ["loc-key": "newMessageInTwake", "loc-args": [String]()],
      ],
      "pusher_notification_client_identifier": clientIdentifier,
    ]
    let data =
      (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
    return String(decoding: data, as: UTF8.self)
  }

  /// Names the account in a push without revealing its Matrix id: the SHA-256 of the id, in hex.
  static func clientIdentifier(_ userId: String) -> String {
    SHA256.hash(data: Data(userId.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
