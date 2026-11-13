import Domain
import Foundation
import MatrixRustSDK

/// `DevicesRepository` on the Matrix client-server API (`/_matrix/client/v3/devices`), which the pinned SDK does not
/// expose, called with the session's access token, as `TwakeContactLookup` calls the ToM server. Nothing here logs:
/// the token and the device names are the user's.
public actor DevicesProxy: DevicesRepository {
  private let clientProxy: @Sendable () async -> ClientProxy?
  private let session: URLSession

  public init(authentication: MatrixAuthenticationRepository) {
    clientProxy = { await authentication.clientProxy }
    session = .shared
  }

  public func devices() async throws(DevicesError) -> [DeviceSession] {
    let (client, request) = try await request(path: "devices", method: "GET", body: nil)
    let currentId = try? client.client.deviceId()
    do {
      let (data, response) = try await session.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw DevicesError.requestFailed
      }
      return Self.sessions(from: data, currentId: currentId)
    } catch {
      throw .requestFailed
    }
  }

  public func rename(deviceId: String, to name: String) async throws(DevicesError) {
    let encoded = deviceId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? deviceId
    let body = try? JSONSerialization.data(withJSONObject: ["display_name": name])
    let (_, request) = try await request(path: "devices/\(encoded)", method: "PUT", body: body)
    do {
      let (_, response) = try await session.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw DevicesError.requestFailed
      }
    } catch {
      throw .requestFailed
    }
  }

  private func request(path: String, method: String, body: Data?) async throws(DevicesError)
    -> (ClientProxy, URLRequest)
  {
    guard let client = await clientProxy(), let session = try? client.client.session(),
      let base = URL(string: session.homeserverUrl)
    else { throw .notSignedIn }
    var request = URLRequest(url: base.appending(path: "_matrix/client/v3/\(path)"))
    request.httpMethod = method
    request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
    if let body {
      request.httpBody = body
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    return (client, request)
  }

  /// The `devices` answer: this session first, then the others by last seen, newest first.
  static func sessions(from data: Data, currentId: String?) -> [DeviceSession] {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let list = object["devices"] as? [[String: Any]]
    else { return [] }
    let sessions = list.compactMap { entry -> DeviceSession? in
      guard let id = entry["device_id"] as? String else { return nil }
      let lastSeen = (entry["last_seen_ts"] as? NSNumber).map {
        Date(timeIntervalSince1970: $0.doubleValue / 1000)
      }
      return DeviceSession(
        id: id, displayName: entry["display_name"] as? String, lastSeen: lastSeen,
        isCurrent: id == currentId)
    }
    return sessions.sorted { lhs, rhs in
      if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
      return (lhs.lastSeen ?? .distantPast) > (rhs.lastSeen ?? .distantPast)
    }
  }
}
