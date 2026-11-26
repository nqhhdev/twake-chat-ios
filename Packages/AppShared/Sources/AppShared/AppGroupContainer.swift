import Foundation

public struct AppGroupContainer: Sendable {
  public static let defaultGroupIdentifier = "group.app.twake.ios.chat"

  static let sdkStorePathComponents = ["Library", "Application Support", "TwakeChat", "SDK"]

  private let groupIdentifier: String

  public init(groupIdentifier: String = AppGroupContainer.defaultGroupIdentifier) {
    self.groupIdentifier = groupIdentifier
  }

  public func sdkStoreDirectory() -> URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
      .map(Self.sdkStoreDirectory(in:))
  }

  public func containerURL() -> URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
  }

  public static func twakeChatDirectory(in containerURL: URL) -> URL {
    sdkStorePathComponents.dropLast().reduce(containerURL) { url, component in
      url.appending(path: component, directoryHint: .isDirectory)
    }
  }

  public static func sdkStoreDirectory(in containerURL: URL) -> URL {
    sdkStorePathComponents.reduce(containerURL) { url, component in
      url.appending(path: component, directoryHint: .isDirectory)
    }
  }
}
