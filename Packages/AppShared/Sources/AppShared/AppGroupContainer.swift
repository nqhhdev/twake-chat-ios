import Foundation

/// Paths inside the App Group container shared by the app and the Notification Service Extension (ADR 0007).
/// The SDK store gets a directory of its own, apart from anything the Flutter app left in the container (ADR 0012).
/// This type only names paths: it creates and deletes nothing.
///
/// The app and the extension must open the same SDK store, so the directory is fixed here and no caller can choose
/// another: `Library/Application Support/TwakeChat/SDK`, the name ADR 0017 open point 4 proposes. It stays pending
/// until the owner confirms it (listed in Open Verifications); a different answer changes only this constant.
public struct AppGroupContainer: Sendable {
  public static let defaultGroupIdentifier = "group.app.twake.ios.chat"

  /// The one SDK store directory, relative to the App Group container.
  static let sdkStorePathComponents = ["Library", "Application Support", "TwakeChat", "SDK"]

  private let groupIdentifier: String

  public init(groupIdentifier: String = AppGroupContainer.defaultGroupIdentifier) {
    self.groupIdentifier = groupIdentifier
  }

  /// The SDK store directory in the App Group container, or `nil` when the process has no access to the group.
  public func sdkStoreDirectory() -> URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
      .map(Self.sdkStoreDirectory(in:))
  }

  /// The SDK store directory inside the given container.
  public static func sdkStoreDirectory(in containerURL: URL) -> URL {
    sdkStorePathComponents.reduce(containerURL) { url, component in
      url.appending(path: component, directoryHint: .isDirectory)
    }
  }
}
