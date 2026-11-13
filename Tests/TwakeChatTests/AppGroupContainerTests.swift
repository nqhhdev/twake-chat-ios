import AppShared
import Foundation
import Testing

/// The App Group container as the signed app sees it on the simulator (ADR 0007). Hosted, because the container needs
/// the app's `com.apple.security.application-groups` entitlement.
struct AppGroupContainerTests {
  @Test func sdkStoreDirectoryIsInsideTheAppGroupContainer() throws {
    let container = try #require(
      FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: AppGroupContainer.defaultGroupIdentifier))
    let directory = try #require(AppGroupContainer().sdkStoreDirectory())
    #expect(directory == AppGroupContainer.sdkStoreDirectory(in: container))
    #expect(directory.path(percentEncoded: false).hasPrefix(container.path(percentEncoded: false)))
  }

  /// Naming the directory creates nothing and deletes nothing (the Flutter cleanup is ADR 0012's, out of scope).
  @Test func askingForTheDirectoryCreatesNothing() throws {
    let container = try #require(
      FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: AppGroupContainer.defaultGroupIdentifier))
    let expected = AppGroupContainer.sdkStoreDirectory(in: container)
    let existedBefore = FileManager.default.fileExists(atPath: expected.path(percentEncoded: false))
    _ = AppGroupContainer().sdkStoreDirectory()
    #expect(FileManager.default.fileExists(atPath: expected.path(percentEncoded: false)) == existedBefore)
  }
}
