import Domain
import Foundation
import MatrixRustSDK

/// `LinkPreviewRepository` on the homeserver's `preview_url` (authenticated media, `/_matrix/client/v1/media`, then
/// the older `/_matrix/media/v3` for a server that lacks it), called with the session's access token as
/// `DevicesProxy` does. Each link is asked once per launch. Nothing here logs: links are the user's.
public actor LinkPreviewProxy: LinkPreviewRepository {
  private let clientProxy: @Sendable () async -> ClientProxy?
  private let session: URLSession
  private var cache: [URL: LinkPreview?] = [:]

  public init(authentication: MatrixAuthenticationRepository) {
    clientProxy = { await authentication.clientProxy }
    session = .shared
  }

  public func preview(of url: URL, inRoom roomId: String) async -> LinkPreview? {
    guard let room = try? await clientProxy()?.client.getRoom(roomId: roomId),
      (try? await room.latestEncryptionState()) == .notEncrypted
    else { return nil }
    if let cached = cache[url] { return cached }
    let preview = await fetch(url)
    cache[url] = preview
    return preview
  }

  private func fetch(_ url: URL) async -> LinkPreview? {
    guard let client = await clientProxy(), let signedIn = try? client.client.session(),
      let base = URL(string: signedIn.homeserverUrl)
    else { return nil }
    for path in ["_matrix/client/v1/media/preview_url", "_matrix/media/v3/preview_url"] {
      var endpoint = base.appending(path: path)
      endpoint.append(queryItems: [URLQueryItem(name: "url", value: url.absoluteString)])
      var request = URLRequest(url: endpoint)
      request.setValue("Bearer \(signedIn.accessToken)", forHTTPHeaderField: "Authorization")
      guard let (data, response) = try? await session.data(for: request),
        let status = (response as? HTTPURLResponse)?.statusCode
      else { return nil }
      if status == 200 { return Self.preview(of: url, from: data) }
      // An unknown endpoint: try the older one; any other answer means no preview.
      guard status == 404 || status == 400 else { return nil }
    }
    return nil
  }

  /// The Open Graph fields of a `preview_url` answer; `nil` when none of them is there.
  static func preview(of url: URL, from data: Data) -> LinkPreview? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    func text(_ key: String) -> String? {
      guard let value = (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
        !value.isEmpty
      else { return nil }
      return value
    }
    var image: MediaReference?
    if let mxc = text("og:image"), mxc.hasPrefix("mxc://"),
      let source = try? MediaSource.fromUrl(url: mxc)
    {
      image = MediaReference(
        source: source.toJson(), mimeType: text("og:image:type") ?? "image/*",
        width: (object["og:image:width"] as? NSNumber)?.intValue,
        height: (object["og:image:height"] as? NSNumber)?.intValue)
    }
    let preview = LinkPreview(
      url: url, title: text("og:title"), description: text("og:description"),
      siteName: text("og:site_name"), image: image)
    return preview.isEmpty ? nil : preview
  }
}
