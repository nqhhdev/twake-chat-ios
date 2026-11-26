import Domain
import Foundation

/// Where an account's Meet calls are made (#92), as the Flutter app finds it: the homeserver's
/// `.well-known/matrix/client` lists a LiveKit focus under `org.matrix.msc4143.rtc_foci`, whose URL is the Meet
/// base URL; ToM (`t.server`) makes a Meet room with `POST /_twake/v1/video_call/rooms`. Nothing here logs.
struct TwakeMeet: Sendable {
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

  private struct CreatedRoom: Decodable {
    let url: String?
  }
}
