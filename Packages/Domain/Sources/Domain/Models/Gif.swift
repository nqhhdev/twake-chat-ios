import Foundation

public struct Gif: Sendable, Equatable, Identifiable {
  public let id: String
  public let title: String
  public let previewURL: URL
  public let url: URL
  public let width: Int
  public let height: Int

  public init(id: String, title: String, previewURL: URL, url: URL, width: Int, height: Int) {
    self.id = id
    self.title = title
    self.previewURL = previewURL
    self.url = url
    self.width = width
    self.height = height
  }
}

public struct GifPage: Sendable, Equatable {
  public let results: [Gif]
  public let next: String?

  public init(results: [Gif], next: String?) {
    self.results = results
    self.next = next
  }
}

public struct GifFile: Sendable, Equatable {
  public let fileURL: URL
  public let mimeType: String
  public let size: Int

  public init(fileURL: URL, mimeType: String, size: Int) {
    self.fileURL = fileURL
    self.mimeType = mimeType
    self.size = size
  }
}

public enum GifError: Error, Sendable, Equatable {
  case expired
  case downloadFailed
}
