import Domain
import Testing

@testable import Room

@MainActor
struct MessageInfoSheetTests {
  @Test func eachKindOfMessageIsNamed() {
    #expect(MessageInfoSheet.kind(of: .text("Hi")) == "Text")
    #expect(MessageInfoSheet.kind(of: .image(caption: nil)) == "Picture")
    #expect(MessageInfoSheet.kind(of: .file(name: "a.pdf")) == "File")
    #expect(MessageInfoSheet.kind(of: .poll(question: "Lunch?")) == "Poll")
    #expect(MessageInfoSheet.kind(of: .redacted) == "Deleted message")
  }
}
