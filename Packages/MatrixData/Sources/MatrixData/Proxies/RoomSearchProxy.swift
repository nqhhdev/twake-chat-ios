import Domain
import Foundation
import MatrixRustSDK

/// `RoomSearchRepository` on the client-server API's `/search`, which the pinned SDK does not expose, called with the
/// session's access token as `DevicesProxy` does. It asks for 20 results a page, newest first, with the senders'
/// profiles, as the Flutter app does. Nothing here logs: the search term and the results are the user's.
public actor RoomSearchProxy: RoomSearchRepository {
  /// Results a page, as the Flutter `ServerSearchController`.
  static let pageSize = 20

  private let clientProxy: @Sendable () async -> ClientProxy?
  private let session: URLSession

  public init(authentication: MatrixAuthenticationRepository) {
    clientProxy = { await authentication.clientProxy }
    session = .shared
  }

  public func search(_ term: String, roomId: String, from nextBatch: String?)
    async throws(RoomSearchError) -> RoomSearchPage
  {
    try await run(term: term, roomId: roomId, from: nextBatch)
  }

  public func searchEverywhere(_ term: String, from nextBatch: String?)
    async throws(RoomSearchError) -> RoomSearchPage
  {
    try await run(term: term, roomId: nil, from: nextBatch)
  }

  private func run(term: String, roomId: String?, from nextBatch: String?)
    async throws(RoomSearchError) -> RoomSearchPage
  {
    guard let client = await clientProxy(), let signedIn = try? client.client.session(),
      let base = URL(string: signedIn.homeserverUrl)
    else { throw .notSignedIn }
    var url = base.appending(path: "_matrix/client/v3/search")
    if let nextBatch {
      url.append(queryItems: [URLQueryItem(name: "next_batch", value: nextBatch)])
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(signedIn.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Self.body(term: term, roomId: roomId)
    do {
      let (data, response) = try await session.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw RoomSearchError.requestFailed
      }
      return Self.page(from: data)
    } catch {
      throw .requestFailed
    }
  }

  /// The request: room events of one room matching the term, newest first, with the senders' profiles.
  static func body(term: String, roomId: String?) -> Data? {
    var filter: [String: Any] = ["limit": pageSize]
    if let roomId { filter["rooms"] = [roomId] }
    let roomEvents: [String: Any] = [
      "search_term": term,
      "order_by": "recent",
      "filter": filter,
      "event_context": ["before_limit": 0, "after_limit": 0, "include_profile": true],
    ]
    return try? JSONSerialization.data(withJSONObject: [
      "search_categories": ["room_events": roomEvents]
    ])
  }

  /// The answer's messages with a text body, and where the next page starts.
  static func page(from data: Data) -> RoomSearchPage {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let categories = object["search_categories"] as? [String: Any],
      let roomEvents = categories["room_events"] as? [String: Any]
    else { return RoomSearchPage(results: [], nextBatch: nil) }
    let entries = roomEvents["results"] as? [[String: Any]] ?? []
    let results = entries.compactMap { entry -> RoomSearchResult? in
      guard let event = entry["result"] as? [String: Any],
        let eventId = event["event_id"] as? String,
        let sender = event["sender"] as? String,
        let content = event["content"] as? [String: Any],
        let body = content["body"] as? String
      else { return nil }
      let profiles = (entry["context"] as? [String: Any])?["profile_info"] as? [String: Any]
      let name = (profiles?[sender] as? [String: Any])?["displayname"] as? String
      let timestamp = (event["origin_server_ts"] as? NSNumber)?.doubleValue ?? 0
      return RoomSearchResult(
        eventId: eventId, senderId: sender,
        senderName: name.flatMap { $0.isEmpty ? nil : $0 } ?? sender,
        date: Date(timeIntervalSince1970: timestamp / 1000), text: body,
        roomId: event["room_id"] as? String)
    }
    return RoomSearchPage(results: results, nextBatch: roomEvents["next_batch"] as? String)
  }
}
