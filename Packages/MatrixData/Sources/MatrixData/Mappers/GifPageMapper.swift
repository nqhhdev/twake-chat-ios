import Domain
import Foundation

enum GifPageMapper {
  static let previewMinWidth = 280

  struct Media: Equatable {
    let size: String
    let format: String
    let url: URL
    let width: Int?
    let height: Int?
    let bytes: Int?
  }

  static func placeholder(_ data: Data) -> String? {
    guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let modules = body["modules"] as? [String: Any],
      let gif = modules["gif"] as? [String: Any],
      let attribution = gif["attribution"] as? [String: Any]
    else { return nil }
    if let placeholder = attribution["searchPlaceholder"] as? String { return placeholder }
    return (attribution["name"] as? String).map { "Search \($0)" }
  }

  static func page(_ data: Data, baseURL: URL) -> GifPage? {
    guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let items = body["results"] as? [Any]
    else { return nil }
    let origin = Self.origin(of: baseURL)
    var results: [Gif] = []
    for case let item as [String: Any] in items {
      guard let id = item["id"] as? String, let list = item["media"] as? [Any] else { continue }
      let media = list.compactMap { entry -> Media? in
        guard let entry = entry as? [String: Any],
          let size = entry["size"] as? String, let format = entry["format"] as? String,
          let link = entry["url"] as? String, let url = URL(string: link, relativeTo: baseURL),
          Self.origin(of: url.absoluteURL) == origin
        else { return nil }
        return Media(
          size: size, format: format, url: url.absoluteURL, width: entry["width"] as? Int,
          height: entry["height"] as? Int, bytes: entry["bytes"] as? Int)
      }
      guard let preview = preview(media),
        let file = first(media, formats: ["gif", "webp"], sizes: ["sm", "md", "hd", "xs"])
      else { continue }
      results.append(
        Gif(
          id: id, title: item["title"] as? String ?? "", previewURL: preview.url, url: file.url,
          width: file.width ?? 0, height: file.height ?? 0))
    }
    return GifPage(results: results, next: body["next"] as? String)
  }

  static func first(_ media: [Media], formats: [String], sizes: [String]) -> Media? {
    for format in formats {
      for size in sizes {
        if let found = media.first(where: { $0.size == size && $0.format == format }) {
          return found
        }
      }
    }
    return nil
  }

  static func preview(_ all: [Media]) -> Media? {
    let ordered = ["sm", "xs", "md", "hd"].flatMap { size in
      ["webp", "gif", "jpg"].flatMap { format in
        all.filter { $0.size == size && $0.format == format }
      }
    }
    let animated = ordered.filter { $0.format == "webp" || $0.format == "gif" }
    let candidates = animated.isEmpty ? ordered.filter { $0.format == "jpg" } : animated
    let wide = candidates.filter { ($0.width ?? 0) >= previewMinWidth }
    guard !wide.isEmpty, wide.allSatisfy({ $0.bytes != nil }) else { return candidates.first }
    return wide.min { ($0.bytes ?? .max) < ($1.bytes ?? .max) }
  }

  static func fileExtension(for mimeType: String) -> String {
    switch mimeType {
    case "image/webp": "webp"
    case "image/png": "png"
    case "image/jpeg": "jpg"
    default: "gif"
    }
  }

  private static func origin(of url: URL) -> String {
    "\(url.scheme ?? "")://\(url.host ?? "")\(url.port.map { ":\($0)" } ?? "")"
  }
}
