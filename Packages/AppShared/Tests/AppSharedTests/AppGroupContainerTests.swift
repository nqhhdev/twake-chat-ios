import AppShared
import Foundation
import Testing

struct AppGroupContainerTests {
  private static let container = URL(
    filePath: "/private/var/mobile/Containers/Shared/AppGroup/ABC", directoryHint: .isDirectory)

  /// The fixed directory ADR 0017 open point 4 proposes, the same for every caller.
  @Test func sdkStoreDirectoryIsTheFixedSubdirectoryOfTheContainer() {
    let directory = AppGroupContainer.sdkStoreDirectory(in: Self.container)
    #expect(
      directory.path(percentEncoded: false)
        == "/private/var/mobile/Containers/Shared/AppGroup/ABC/Library/Application Support/TwakeChat/SDK/"
    )
    #expect(directory.hasDirectoryPath)
  }

  /// The Flutter app's trees in the container (ADR 0017 drop list) are deleted by the first-launch cleanup (ADR 0012):
  /// the SDK store must not be one of them, inside one, or hold one.
  @Test(arguments: [
    "Library/Application Support/app.twake.ios.chat/",
    "Library/Caches/",
  ])
  func sdkStoreDirectoryIsApartFromFlutterTree(flutterTree: String) {
    let base = Self.container.path(percentEncoded: false)
    let store = AppGroupContainer.sdkStoreDirectory(in: Self.container).path(percentEncoded: false)
    let flutter = base + flutterTree
    #expect(!store.hasPrefix(flutter))
    #expect(!flutter.hasPrefix(store))
  }

  @Test func defaultGroupIsTheAppGroup() {
    #expect(AppGroupContainer.defaultGroupIdentifier == "group.app.twake.ios.chat")
  }
}
