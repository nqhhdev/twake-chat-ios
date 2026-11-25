import Domain
import Foundation
import Testing

/// The state `app.twake.chat.page_style` is read as the web client writes it.
struct PageStyleTests {
  private func style(_ json: String) throws -> PageStyle? {
    let content = try #require(
      try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    return PageStyle(content: content) { MediaReference(source: $0) }
  }

  @Test func readsTheCoverAndColourTheWebWrites() throws {
    let read = try style(##"{"cover_url":"mxc://example.org/abc","accent_color":"#3F51B5"}"##)
    #expect(read?.cover == MediaReference(source: "mxc://example.org/abc"))
    #expect(read?.accentColor == "#3f51b5")
    let rgb = try #require(read?.accentRGB)
    #expect(rgb.red == 0x3F / 255.0)
    #expect(rgb.green == 0x51 / 255.0)
    #expect(rgb.blue == 0xB5 / 255.0)
  }

  @Test func readsAColourWithoutCoverAndACoverWithoutColour() throws {
    #expect(
      try style(##"{"accent_color":"#00ff00"}"##) == PageStyle(cover: nil, accentColor: "#00ff00"))
    #expect(
      try style(##"{"cover_url":"mxc://s/c"}"##)
        == PageStyle(cover: MediaReference(source: "mxc://s/c"), accentColor: nil))
  }

  @Test func anEmptyContentDrawsNothing() throws {
    #expect(try style("{}") == nil)
  }

  @Test func leavesOutValuesThatCannotBeDrawn() throws {
    #expect(try style(##"{"cover_url":42,"accent_color":true}"##) == nil)
    #expect(try style(##"{"cover_url":"https://example.org/c.png","accent_color":"red"}"##) == nil)
    #expect(try style(##"{"accent_color":"#abc"}"##) == nil)
    #expect(try style(##"{"accent_color":"#gggggg"}"##) == nil)
    #expect(try style(##"{"accent_color":"3f51b5"}"##) == nil)
    #expect(
      try style(##"{"cover_url":"ftp://x","accent_color":"#112233"}"##)
        == PageStyle(cover: nil, accentColor: "#112233"))
  }

  @Test func aCoverThatCannotBeLoadedIsLeftOut() throws {
    let content: [String: Any] = ["cover_url": "mxc://s/c", "accent_color": "#112233"]
    #expect(
      PageStyle(content: content) { _ in nil } == PageStyle(cover: nil, accentColor: "#112233"))
    #expect(PageStyle(content: ["cover_url": "mxc://s/c"]) { _ in nil } == nil)
  }

  @Test func theEventTypeIsTheWebs() {
    #expect(PageStyle.stateEventType == "app.twake.chat.page_style")
  }
}
