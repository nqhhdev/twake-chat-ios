import Foundation

public protocol GifRepository: Sendable {
  func searchPlaceholder() async -> String?
  func trending(cursor: String?, locale: String) async -> GifPage?
  func search(_ query: String, cursor: String?, locale: String) async -> GifPage?
  func download(_ gif: Gif) async throws(GifError) -> GifFile
}
