import Domain
import Foundation

public final class FakeGifRepository: GifRepository, @unchecked Sendable {
  public enum Call: Equatable, Sendable {
    case placeholder
    case trending(String?, String)
    case search(String, String?, String)
    case download(String)
  }

  private let lock = NSLock()
  private var _calls: [Call] = []
  private var _placeholder: String? = "Search KLIPY"
  private var _pages: [String: GifPage] = [:]
  private var _downloadResult: Result<GifFile, GifError>?

  public init() {}

  public var calls: [Call] { lock.withLock { _calls } }

  public var placeholder: String? {
    get { lock.withLock { _placeholder } }
    set { lock.withLock { _placeholder = newValue } }
  }

  public func setPage(_ page: GifPage?, search: String = "", cursor: String? = nil) {
    lock.withLock { _pages[Self.key(search, cursor)] = page }
  }

  public var downloadResult: Result<GifFile, GifError>? {
    get { lock.withLock { _downloadResult } }
    set { lock.withLock { _downloadResult = newValue } }
  }

  public func searchPlaceholder() async -> String? {
    lock.withLock {
      _calls.append(.placeholder)
      return _placeholder
    }
  }

  public func trending(cursor: String?, locale: String) async -> GifPage? {
    lock.withLock {
      _calls.append(.trending(cursor, locale))
      return _pages[Self.key("", cursor)]
    }
  }

  public func search(_ query: String, cursor: String?, locale: String) async -> GifPage? {
    lock.withLock {
      _calls.append(.search(query, cursor, locale))
      return _pages[Self.key(query, cursor)]
    }
  }

  public func download(_ gif: Gif) async throws(GifError) -> GifFile {
    let result = lock.withLock {
      _calls.append(.download(gif.id))
      return _downloadResult
    }
    guard let result else { throw .downloadFailed }
    return try result.get()
  }

  private static func key(_ search: String, _ cursor: String?) -> String {
    search + "|" + (cursor ?? "")
  }
}
