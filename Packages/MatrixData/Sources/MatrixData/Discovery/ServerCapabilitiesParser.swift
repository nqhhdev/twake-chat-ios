import Domain
import Foundation

enum ServerCapabilitiesParser {
  static func capabilities(
    wellKnown: Data?, versions: Data?, serverName: String, homeserver: URL?, build: BuildServices
  ) -> ServerCapabilities {
    let document = wellKnown.flatMap(object) ?? [:]
    let chat = document["app.twake.chat"] as? [String: Any] ?? [:]
    return ServerCapabilities(
      homeserver: baseURL(document["m.homeserver"]) ?? homeserver,
      identityServer: baseURL(document["m.identity_server"]),
      tom: tom(document["app.twake.tom"] ?? document["t.server"], serverName: serverName),
      callFoci: callFoci(document["org.matrix.msc4143.rtc_foci"]),
      twakeChat: ServerCapabilities.TwakeChat(
        supportContact: nonEmpty(chat["support_contact"]),
        commonSettingsURL: commonSettings(chat["common_settings"]),
        invitationsEnabled: chat["enable_invitations"] as? Bool ?? false,
        sideService: baseURL(chat["side_service"]) ?? baseURL(chat["assistants"]),
        webURL: nonEmpty(chat["web_url"]).flatMap(URL.init(string:)),
        driveEnabled: chat["enable_twake_drive"] as? Bool ?? false),
      unstableFeatures: unstableFeatures(versions),
      build: build,
      authenticationIssuer: wellKnown.flatMap(HomeserverDiscovery.authenticationIssuer))
  }

  static func serverName(ofUserId userId: String) -> String? {
    guard let colon = userId.firstIndex(of: ":") else { return nil }
    let name = userId[userId.index(after: colon)...]
    return name.isEmpty ? nil : String(name)
  }

  private static func object(_ data: Data) -> [String: Any]? {
    try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }

  private static func nonEmpty(_ value: Any?) -> String? {
    guard let text = value as? String, !text.isEmpty else { return nil }
    return text
  }

  private static func baseURL(_ value: Any?) -> URL? {
    guard let object = value as? [String: Any], let text = nonEmpty(object["base_url"]),
      let url = URL(string: text), url.host() != nil
    else { return nil }
    return url
  }

  private static func tom(_ value: Any?, serverName: String) -> ServerCapabilities.Tom? {
    guard let object = value as? [String: Any], let text = object["base_url"] as? String,
      let url = URL(string: text)
    else { return nil }
    return ServerCapabilities.Tom(
      baseURL: url, serverName: nonEmpty(object["server_name"]) ?? serverName)
  }

  private static func callFoci(_ value: Any?) -> [URL] {
    guard let foci = value as? [Any] else { return [] }
    return foci.compactMap { entry in
      guard let focus = entry as? [String: Any], focus["type"] as? String == "livekit",
        let text = nonEmpty(focus["livekit_service_url"]) ?? nonEmpty(focus["livekit_base_url"])
      else { return nil }
      return URL(string: text)
    }
  }

  private static func commonSettings(_ value: Any?) -> String? {
    guard let object = value as? [String: Any], object["enabled"] as? Bool != false else {
      return nil
    }
    return nonEmpty(object["application_url"])
  }

  private static func unstableFeatures(_ versions: Data?) -> Set<String> {
    guard let features = versions.flatMap(object)?["unstable_features"] as? [String: Any] else {
      return []
    }
    return Set(features.compactMap { $0.value as? Bool == true ? $0.key : nil })
  }
}
