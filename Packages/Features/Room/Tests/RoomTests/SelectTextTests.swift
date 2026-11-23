import Domain
import Foundation
import Testing

@testable import Room

@MainActor
struct SelectTextTests {
  private func selectable(_ body: TimelineMessage.Body, formatted: AttributedString? = nil)
    -> String?
  {
    MessageBody.selectableText(of: body, formatted: formatted).map { String($0.characters) }
  }

  @Test func textNoticeAndEmoteOfferIt() {
    #expect(selectable(.text("Hello there")) == "Hello there")
    #expect(selectable(.notice("Server notice")) == "Server notice")
    #expect(selectable(.emote("waves")) == "* waves")
  }

  @Test func formattedTextIsKeptWithItsLinks() throws {
    var formatted = AttributedString("see example.com")
    let url = try #require(URL(string: "https://example.com"))
    formatted[try #require(formatted.range(of: "example.com"))].link = url
    let text = try #require(
      MessageBody.selectableText(of: .text("see example.com"), formatted: formatted))
    #expect(text.runs.contains { $0.link == url })
  }

  @Test func messagesWithoutTheirOwnTextDoNot() {
    #expect(selectable(.image(caption: "A caption")) == nil)
    #expect(selectable(.video(caption: nil)) == nil)
    #expect(selectable(.audio(caption: nil)) == nil)
    #expect(selectable(.file(name: "a.pdf")) == nil)
    #expect(selectable(.sticker("😀")) == nil)
    #expect(selectable(.poll(question: "Lunch?")) == nil)
    #expect(selectable(.location("Here", place: nil)) == nil)
    #expect(selectable(.redacted) == nil)
    #expect(selectable(.unableToDecrypt(.unknown)) == nil)
    #expect(selectable(.unsupported) == nil)
  }

  @Test func anEmptyTextDoesNot() {
    #expect(selectable(.text("  \n")) == nil)
  }
}
