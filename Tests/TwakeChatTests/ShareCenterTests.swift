import AppShared
import Foundation
import Testing

@testable import TwakeChat

/// Shares from other apps wait for a chat, then go to it once; Cancel drops them.
@MainActor
struct ShareCenterTests {
  private func inbox(with items: SharedItems) throws -> SharedInbox {
    let inbox = SharedInbox(
      root: FileManager.default.temporaryDirectory.appending(path: "share-\(UUID())"))
    let folder = try inbox.begin()
    for file in items.files { try Data([1]).write(to: folder.appending(path: file.name)) }
    try inbox.finish(items)
    return inbox
  }

  @Test func aShareIsTakenOnceWithItsFiles() throws {
    let items = SharedItems(text: "hi", files: [.init(name: "p.jpg", kind: .image)])
    let inbox = try inbox(with: items)
    let center = ShareCenter(inbox: inbox)
    center.load()
    #expect(center.pending == items)
    let share = try #require(center.take())
    #expect(share.text == "hi")
    #expect(share.files.map(\.lastPathComponent) == ["p.jpg"])
    #expect(center.pending == nil)
    #expect(center.take() == nil)
    share.done()
    #expect(inbox.pending() == nil)
  }

  @Test func cancelDropsTheShare() throws {
    let inbox = try inbox(with: SharedItems(text: "hi"))
    let center = ShareCenter(inbox: inbox)
    center.load()
    center.cancel()
    #expect(center.pending == nil)
    #expect(inbox.pending() == nil)
  }

  @Test func aSuggestedShareSkipsThePicker() throws {
    let inbox = try inbox(with: SharedItems(text: "hi", roomId: "!a:x"))
    let center = ShareCenter(inbox: inbox)
    center.load()
    #expect(center.pending == nil)
    #expect(center.suggested?.roomId == "!a:x")
    #expect(center.takeSuggested(for: "!b:x") == nil)
    let share = try #require(center.takeSuggested(for: "!a:x"))
    #expect(share.text == "hi")
    #expect(center.suggested == nil)
    #expect(center.takeSuggested(for: "!a:x") == nil)
  }

  @Test func anUnknownSuggestedChatFallsBackToThePicker() throws {
    let inbox = try inbox(with: SharedItems(text: "hi", roomId: "!gone:x"))
    let center = ShareCenter(inbox: inbox)
    center.load()
    center.pickInstead(of: "!other:x")
    #expect(center.pending == nil)
    center.pickInstead(of: "!gone:x")
    #expect(center.suggested == nil)
    #expect(center.pending == SharedItems(text: "hi"))
  }

  @Test func aPlainShareReplacesAWaitingSuggestion() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "share-\(UUID())")
    let inbox = SharedInbox(root: root)
    _ = try inbox.begin()
    try inbox.finish(SharedItems(text: "first", roomId: "!a:x"))
    let center = ShareCenter(inbox: inbox)
    center.load()
    _ = try inbox.begin()
    try inbox.finish(SharedItems(text: "second"))
    center.load()
    #expect(center.suggested == nil)
    #expect(center.pending?.text == "second")
  }

  @Test func theSheetCountsWhatIsShared() {
    let files: [SharedItems.File] = [
      .init(name: "a", kind: .image), .init(name: "b", kind: .image), .init(name: "c", kind: .file),
    ]
    #expect(ShareTargetSheet.counts(files) == "2 pictures, 1 file")
  }
}
