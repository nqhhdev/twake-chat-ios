import Domain
import Foundation

/// Where an account's Meet calls are made (#92), as the Flutter app finds it: the homeserver's
/// `.well-known/matrix/client` lists a LiveKit focus under `org.matrix.msc4143.rtc_foci`, whose URL is the Meet
/// base URL; ToM (`t.server`) makes a Meet room with `POST /_twake/v1/video_call/rooms`. Nothing here logs.
struct TwakeMeet: Sendable {
  /// What the well-known announces for calls.
  struct Services: Sendable, Equatable {
    /// The Meet base URL, already passed through `MeetLink.base`.
    let meetBase: URL?
    let tom: URL?
  }

  /// What ToM answered to a new Meet room.
  enum NewRoom: Sendable, Equatable {
    case created(URL)
    /// ToM makes no room on this server (404), or none for this user (422): the app picks the slug itself.
    case unavailable
    case failed
  }

  /// How long ToM has to make a room, as in the Flutter app.
  static let createRoomTimeout: TimeInterval = 20

  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  /// The call services of the user's server name (the part of the Matrix id after the colon), or `nil` when its
  /// well-known cannot be read.
  func services(forUserId userId: String) async -> Services? {
    guard let serverName = userId.split(separator: ":", maxSplits: 1).last.map(String.init),
      let url = URL(string: "https://\(serverName)/.well-known/matrix/client"),
      case (let data, let response)? = try? await session.data(from: url),
      (response as? HTTPURLResponse)?.statusCode == 200,
      let wellKnown = try? JSONDecoder().decode(WellKnown.self, from: data)
    else { return nil }
    // The first LiveKit focus with a usable URL: `livekit_service_url` in MSC4143, `livekit_base_url` in Twake's.
    let meetBase = (wellKnown.rtcFoci ?? []).lazy
      .filter { $0.type == "livekit" }
      .compactMap {
        ($0.serviceURL ?? $0.baseURL).flatMap(URL.init(string:)).flatMap(MeetLink.base)
      }
      .first
    return Services(meetBase: meetBase, tom: wellKnown.tServer.flatMap { URL(string: $0.baseURL) })
  }

  /// A new Meet room made by ToM, with the user's Matrix access token.
  func createRoom(tom: URL, accessToken: String) async -> NewRoom {
    var request = URLRequest(
      url: tom.appending(path: "_twake/v1/video_call/rooms"),
      timeoutInterval: Self.createRoomTimeout)
    request.httpMethod = "POST"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data("{}".utf8)
    guard case (let data, let response)? = try? await session.data(for: request),
      let status = (response as? HTTPURLResponse)?.statusCode
    else { return .failed }
    if status == 404 || status == 422 { return .unavailable }
    guard (200..<300).contains(status),
      let body = try? JSONDecoder().decode(CreatedRoom.self, from: data),
      let url = body.url.flatMap(URL.init(string:))
    else { return .failed }
    return .created(url)
  }

  private struct WellKnown: Decodable {
    struct Focus: Decodable {
      let type: String?
      let serviceURL: String?
      let baseURL: String?
      enum CodingKeys: String, CodingKey {
        case type
        case serviceURL = "livekit_service_url"
        case baseURL = "livekit_base_url"
      }
    }
    struct TServer: Decodable {
      let baseURL: String
      enum CodingKeys: String, CodingKey { case baseURL = "base_url" }
    }
    let rtcFoci: [Focus]?
    let tServer: TServer?

    enum CodingKeys: String, CodingKey {
      case rtcFoci = "org.matrix.msc4143.rtc_foci"
      case tServer = "t.server"
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      // A malformed entry never hides the other one.
      rtcFoci = try? container.decodeIfPresent([Focus].self, forKey: .rtcFoci)
      tServer = try? container.decodeIfPresent(TServer.self, forKey: .tServer)
    }
  }

  private struct CreatedRoom: Decodable {
    let url: String?
  }
}
