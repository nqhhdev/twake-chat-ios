import Foundation

struct ElementCallDiscovery: Sendable {
  struct Services: Sendable, Equatable {
    let livekitService: URL?
    let widgetURL: URL?
  }

  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func services(forUserId userId: String) async -> Services? {
    guard let serverName = userId.split(separator: ":", maxSplits: 1).dropFirst().first,
      let client = URL(string: "https://\(serverName)/.well-known/matrix/client"),
      let element = URL(string: "https://\(serverName)/.well-known/element/element.json")
    else { return nil }
    async let clientData = json(client, as: ClientWellKnown.self)
    async let elementData = json(element, as: ElementWellKnown.self)
    guard let wellKnown = await clientData else { return nil }
    let livekitService = (wellKnown.rtcFoci ?? []).lazy
      .filter { $0.type == "livekit" }
      .compactMap { $0.serviceURL.flatMap(Self.httpsURL) }
      .first
    let widgetURL = await elementData?.call?.widgetURL.flatMap(Self.httpsURL)
    return Services(livekitService: livekitService, widgetURL: widgetURL)
  }

  static func httpsURL(_ text: String) -> URL? {
    guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)),
      url.scheme?.lowercased() == "https", url.host() != nil
    else { return nil }
    return url
  }

  private func json<T: Decodable>(_ url: URL, as type: T.Type) async -> T? {
    guard case (let data, let response)? = try? await session.data(from: url),
      (response as? HTTPURLResponse)?.statusCode == 200
    else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }

  private struct ClientWellKnown: Decodable {
    struct Focus: Decodable {
      let type: String?
      let serviceURL: String?
      enum CodingKeys: String, CodingKey {
        case type
        case serviceURL = "livekit_service_url"
      }
    }
    let rtcFoci: [Focus]?
    enum CodingKeys: String, CodingKey { case rtcFoci = "org.matrix.msc4143.rtc_foci" }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      rtcFoci = try? container.decodeIfPresent([Focus].self, forKey: .rtcFoci)
    }
  }

  private struct ElementWellKnown: Decodable {
    struct Call: Decodable {
      let widgetURL: String?
      enum CodingKeys: String, CodingKey { case widgetURL = "widget_url" }
    }
    let call: Call?
  }
}
