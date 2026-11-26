import Foundation
import Testing

@testable import Domain

struct EmoteTests {
  private func emote(_ shortcode: String) -> Emote {
    Emote(
      shortcode: shortcode, url: "mxc://example.org/\(shortcode)",
      media: MediaReference(source: "mxc://example.org/\(shortcode)"))
  }

  @Test func anEmoticonImageKeepsItsShortcodeAndSource() {
    let text = MatrixHTML.attributedString(
      from:
        #"Hi <img data-mx-emoticon src="mxc://example.org/cat" alt=":cat:" title=":cat:" height="32"> there"#
    )
    #expect(String(text.characters) == "Hi :cat: there")
    #expect(text.hasEmotes)
    let sources = text.runs.compactMap { $0[EmoteAttribute.self] }
    #expect(sources == ["mxc://example.org/cat"])
  }

  @Test func anOrdinaryImageIsOnlyItsAltText() {
    let text = MatrixHTML.attributedString(from: #"<img src="mxc://example.org/a" alt="photo">"#)
    #expect(String(text.characters) == "photo")
    #expect(!text.hasEmotes)
  }

  @Test func shortcodesStartingWithTheQueryComeFirst() {
    let all = [emote("happycat"), emote("cat"), emote("dog"), emote("catjam")]
    #expect(Emote.matching("cat", in: all).map(\.shortcode) == ["cat", "catjam", "happycat"])
    #expect(Emote.matching("CAT", in: all, limit: 1).map(\.shortcode) == ["cat"])
  }
}
