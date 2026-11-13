import AppShared
import Foundation
import Testing

/// The share extension's inbox: one pending share at a time, read back by the app.
struct SharedInboxTests {
  private func inbox() -> SharedInbox {
    SharedInbox(root: FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID())"))
  }

  @Test func aFinishedShareIsReadBackWithItsFiles() throws {
    let inbox = inbox()
    let folder = try inbox.begin()
    try Data("hello".utf8).write(to: folder.appending(path: "a.txt"))
    let items = SharedItems(text: "see this", files: [.init(name: "a.txt", kind: .file)])
    try inbox.finish(items)
    #expect(inbox.pending() == items)
    let file = try #require(inbox.pending()?.files.first)
    #expect(try String(contentsOf: inbox.url(of: file), encoding: .utf8) == "hello")
    inbox.clear()
    #expect(inbox.pending() == nil)
  }

  @Test func aNewShareReplacesTheLastOne() throws {
    let inbox = inbox()
    _ = try inbox.begin()
    try inbox.finish(SharedItems(text: "first"))
    _ = try inbox.begin()
    #expect(inbox.pending() == nil)
    try inbox.finish(SharedItems(text: "second"))
    #expect(inbox.pending()?.text == "second")
    inbox.clear()
  }

  @Test func aShareWithNothingIsEmpty() {
    #expect(SharedItems().isEmpty)
    #expect(SharedItems(text: "").isEmpty)
    #expect(SharedItems(files: [.init(name: "a", kind: .image)]).isEmpty == false)
  }
}
