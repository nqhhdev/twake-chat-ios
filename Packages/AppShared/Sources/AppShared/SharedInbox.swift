import Foundation

/// What another app shared into Twake Chat: text (a web link is text) and files. The share extension writes it into
/// the App Group container and opens the app, which asks which chat to send it to, as the Flutter app's share
/// extension (`receive_sharing_intent`) does.
public struct SharedItems: Codable, Sendable, Equatable {
  public struct File: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
      case image
      case video
      case file
    }

    /// The file's name inside the share's folder.
    public let name: String
    public let kind: Kind

    public init(name: String, kind: Kind) {
      self.name = name
      self.kind = kind
    }
  }

  public var text: String?
  public var files: [File]
  public var roomId: String?
  public var accountUserId: String?

  public init(
    text: String? = nil, files: [File] = [], roomId: String? = nil, accountUserId: String? = nil
  ) {
    self.text = text
    self.files = files
    self.roomId = roomId
    self.accountUserId = accountUserId
  }

  public var isEmpty: Bool { (text ?? "").isEmpty && files.isEmpty }
}

/// The one pending share, in the App Group container: a folder of files and a `manifest.json`. A new share replaces
/// the last one.
public struct SharedInbox: Sendable {
  /// The link the share extension opens the app with.
  public static let openURL = URL(string: "twake.chat://share")!

  private let root: URL

  public init(root: URL) {
    self.root = root
  }

  /// The inbox in the app's App Group, or `nil` when this process cannot reach the group.
  public static func inAppGroup(
    _ identifier: String = AppGroupContainer.defaultGroupIdentifier
  ) -> SharedInbox? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier).map {
      SharedInbox(root: $0.appending(path: "Library/Caches/Shared", directoryHint: .isDirectory))
    }
  }

  private var manifestURL: URL { root.appending(path: "manifest.json") }

  /// Starts a share: drops the previous one and returns the empty folder its files go in.
  public func begin() throws -> URL {
    clear()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  /// Saves what was shared once its files are in the folder.
  public func finish(_ items: SharedItems) throws {
    try JSONEncoder().encode(items).write(to: manifestURL, options: .atomic)
  }

  /// The pending share, or `nil`.
  public func pending() -> SharedItems? {
    guard let data = try? Data(contentsOf: manifestURL) else { return nil }
    return try? JSONDecoder().decode(SharedItems.self, from: data)
  }

  /// Where a shared file is.
  public func url(of file: SharedItems.File) -> URL {
    root.appending(path: file.name)
  }

  /// Removes the pending share and its files.
  public func clear() {
    try? FileManager.default.removeItem(at: root)
  }
}
