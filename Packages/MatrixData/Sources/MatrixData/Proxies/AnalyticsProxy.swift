import Domain
import Foundation
import MatrixRustSDK

public actor AnalyticsProxy: AnalyticsRepository {
  private let clientProxy: @Sendable () async -> ClientProxy?
  private let session: URLSession

  public init(authentication: MatrixAuthenticationRepository) {
    clientProxy = { await authentication.clientProxy }
    session = .shared
  }

  public func consent() async -> AnalyticsConsent? {
    guard let client = await clientProxy()?.client,
      let json = try? await client.accountData(eventType: AnalyticsConsent.accountDataType)
    else { return nil }
    return AnalyticsPayload.consent(fromJSON: Data(json.utf8))
  }

  public func setConsent(_ consent: AnalyticsConsent) async throws(SettingsError) {
    guard let client = await clientProxy()?.client else { throw .notSignedIn }
    guard let content = AnalyticsPayload.json(consent) else { throw .requestFailed }
    do {
      try await client.setAccountData(
        eventType: AnalyticsConsent.accountDataType, content: content)
    } catch {
      throw .requestFailed
    }
  }

  public func send(_ events: [AnalyticsEvent], to endpoint: URL, appVersion: String) async -> Bool {
    guard let token = await GifProxy.openIDToken(client: await clientProxy()),
      let body = AnalyticsPayload.body(events, appVersion: appVersion)
    else { return false }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue(token.serverName, forHTTPHeaderField: "x-matrix-server-name")
    guard case (_, let response)? = try? await session.data(for: request),
      let status = (response as? HTTPURLResponse)?.statusCode
    else { return false }
    return (200..<300).contains(status)
  }
}

enum AnalyticsPayload {
  static func consent(fromJSON data: Data) -> AnalyticsConsent? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let granted = object["granted"] as? Bool
    else { return nil }
    let at = (object["at"] as? String).flatMap(date) ?? .distantPast
    return AnalyticsConsent(granted: granted, at: at)
  }

  static func json(_ consent: AnalyticsConsent) -> String? {
    guard
      let data = try? JSONSerialization.data(
        withJSONObject: ["granted": consent.granted, "at": string(consent.at)],
        options: [.sortedKeys])
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func body(_ events: [AnalyticsEvent], appVersion: String) -> Data? {
    let list: [[String: Any]] = events.map { event in
      [
        "name": event.name, "at": string(event.at),
        "properties": event.properties.mapValues { value -> Any in
          switch value {
          case .string(let text): text
          case .int(let number): number
          case .bool(let flag): flag
          }
        },
      ]
    }
    return try? JSONSerialization.data(
      withJSONObject: ["app": "twake-chat", "version": appVersion, "events": list],
      options: [.sortedKeys])
  }

  private static func string(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  private static func date(_ text: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: text) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)
  }
}
