import Domain
import Foundation
import MatrixRustSDK

/// `DevicesRepository` on the Matrix client-server API (`/_matrix/client/v3/devices`), which the pinned SDK does not
/// expose, called with the session's access token, as `TwakeContactLookup` calls the ToM server. Nothing here logs:
/// the token and the device names are the user's.
public actor DevicesProxy: DevicesRepository, AccountDeletionRepository {
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

  public func signOut(deviceIds: [String], auth: DeviceAuth?) async throws(DevicesError)
    -> DeviceSignOut
  {
    guard !deviceIds.isEmpty else { return .done }
    var payload: [String: Any] = ["devices": deviceIds]
    if let auth {
      let userId = try? await clientProxy()?.userId
      payload["auth"] = try await Self.authBody(auth, userId: userId)
    }
    let body = try? JSONSerialization.data(withJSONObject: payload)
    let (_, request) = try await request(path: "delete_devices", method: "POST", body: body)
    let data: Data
    let status: Int
    do {
      let (answer, response) = try await session.data(for: request)
      data = answer
      status = (response as? HTTPURLResponse)?.statusCode ?? 0
    } catch {
      throw .requestFailed
    }
    if status == 200 { return .done }
    guard status == 401,
      let challenge = Self.challenge(
        from: data, homeserver: request.url?.deletingLastPathComponent())
    else { throw .requestFailed }
    return .needsConfirmation(challenge)
  }

  public func deactivateAccount(auth: DeviceAuth?) async throws(DevicesError) -> AccountDeletion {
    var payload: [String: Any] = ["erase": false]
    if let auth {
      let userId = try? await clientProxy()?.userId
      payload["auth"] = try await Self.authBody(auth, userId: userId)
    }
    let body = try? JSONSerialization.data(withJSONObject: payload)
    let (_, request) = try await request(path: "account/deactivate", method: "POST", body: body)
    let data: Data
    let status: Int
    do {
      let (answer, response) = try await session.data(for: request)
      data = answer
      status = (response as? HTTPURLResponse)?.statusCode ?? 0
    } catch {
      throw .requestFailed
    }
    if status == 200 { return .done }
    guard status == 401,
      let challenge = Self.challenge(
        from: data, homeserver: request.url?.deletingLastPathComponent().deletingLastPathComponent()
      )
    else { throw .requestFailed }
    return .needsConfirmation(challenge)
  }

  /// The `auth` object of the retry: the session alone after the SSO fallback page (spec, "Fallback"), or the password
  /// with the user's id.
  static func authBody(_ auth: DeviceAuth, userId: String?) async throws(DevicesError) -> [String:
    Any]
  {
    switch auth {
    case .confirmedOnWeb(let session):
      return ["session": session]
    case .password(let password, let session):
      guard let userId else { throw .notSignedIn }
      return [
        "type": "m.login.password", "session": session, "password": password,
        "identifier": ["type": "m.id.user", "user": userId],
      ]
    }
  }

  /// The challenge in a 401 answer: its session, the SSO fallback page when a flow uses `m.login.sso`, and whether a
  /// flow is the password alone. `base` is the homeserver's `_matrix/client/v3/` URL.
  static func challenge(from data: Data, homeserver base: URL?) -> DeviceAuthChallenge? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let session = object["session"] as? String
    else { return nil }
    let flows = (object["flows"] as? [[String: Any]] ?? []).compactMap { $0["stages"] as? [String] }
    let usesSSO = flows.contains { $0 == ["m.login.sso"] }
    var webURL: URL?
    if usesSSO, let base {
      var components = URLComponents(
        url: base.appending(path: "auth/m.login.sso/fallback/web"), resolvingAgainstBaseURL: false)
      components?.queryItems = [URLQueryItem(name: "session", value: session)]
      webURL = components?.url
    }
    return DeviceAuthChallenge(
      session: session, webURL: webURL,
      acceptsPassword: flows.contains { $0 == ["m.login.password"] })
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
