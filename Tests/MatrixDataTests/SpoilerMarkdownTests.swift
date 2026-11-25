import Foundation
import Testing

@testable import MatrixData

struct SpoilerMarkdownTests {
  @Test func barsAroundTextMakeASpoilerAndAnOddBarStaysText() {
    #expect(
      SpoilerMarkdown.segments("a ||b|| c ||d")
        == [
          .init(text: "a ", isSpoiler: false), .init(text: "b", isSpoiler: true),
          .init(text: " c ||d", isSpoiler: false),
        ])
    #expect(SpoilerMarkdown.segments("a |||| b") == [.init(text: "a |||| b", isSpoiler: false)])
  }

  @Test func aTextWithoutSpoilerIsLeftToTheMarkdownOfTheSdk() {
    #expect(SpoilerMarkdown.content("plain **bold**") == nil)
  }

  @Test func theSpoilerIsHiddenInTheBodyAndMarkedInTheHtml() throws {
    let content = try #require(SpoilerMarkdown.content("Bruce **is** ||the _bat_ <man>||!"))
    #expect(content.body == "Bruce **is** [Spoiler]!")
    #expect(
      content.html
        == "Bruce <strong>is</strong> <span data-mx-spoiler>the <em>bat</em> &lt;man&gt;</span>!")
  }

  @Test func linksAndNewLinesKeepTheirMeaning() {
    #expect(
      SpoilerMarkdown.inlineHTML("see [Bob](https://matrix.to/#/@bob:example.org)\nnow")
        == "see <a href=\"https://matrix.to/#/@bob:example.org\">Bob</a><br>now")
  }
}
