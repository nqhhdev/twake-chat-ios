import Foundation
import Testing

@testable import MatrixData

struct RichMarkdownTests {
  @Test func barsAroundTextMakeASpoilerAndAnOddBarStaysText() {
    #expect(
      RichMarkdown.segments("a ||b|| c ||d")
        == [
          .init(text: "a ", isSpoiler: false), .init(text: "b", isSpoiler: true),
          .init(text: " c ||d", isSpoiler: false),
        ])
    #expect(RichMarkdown.segments("a |||| b") == [.init(text: "a |||| b", isSpoiler: false)])
  }

  @Test func aTextWithoutSpoilerIsLeftToTheMarkdownOfTheSdk() {
    #expect(RichMarkdown.content("plain **bold**") == nil)
  }

  @Test func theSpoilerIsHiddenInTheBodyAndMarkedInTheHtml() throws {
    let content = try #require(RichMarkdown.content("Bruce **is** ||the _bat_ <man>||!"))
    #expect(content.body == "Bruce **is** [Spoiler]!")
    #expect(
      content.html
        == "Bruce <strong>is</strong> <span data-mx-spoiler>the <em>bat</em> &lt;man&gt;</span>!")
  }

  @Test func linksAndNewLinesKeepTheirMeaning() {
    #expect(
      RichMarkdown.inlineHTML("see [Bob](https://matrix.to/#/@bob:example.org)\nnow")
        == "see <a href=\"https://matrix.to/#/@bob:example.org\">Bob</a><br>now")
  }

  @Test func aKnownShortcodeBecomesAnEmoticonImageOutsideCode() throws {
    let emotes = ["cat": "mxc://example.org/cat"]
    let content = try #require(RichMarkdown.content("hi :cat: `:cat:` :dog:", emotes: emotes))
    #expect(content.body == "hi :cat: `:cat:` :dog:")
    #expect(
      content.html
        == "hi <img data-mx-emoticon src=\"mxc://example.org/cat\" alt=\":cat:\" title=\":cat:\" height=\"32\"> <code>:cat:</code> :dog:"
    )
    #expect(RichMarkdown.content("hi :dog:", emotes: emotes) == nil)
  }
}
