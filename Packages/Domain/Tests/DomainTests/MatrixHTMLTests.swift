import Domain
import Foundation
import Testing

@Suite struct MatrixHTMLTests {
  private func render(_ html: String) -> AttributedString {
    MatrixHTML.attributedString(from: html)
  }

  private func text(_ html: String) -> String { String(render(html).characters) }

  /// The style of the first run whose text is `word`.
  private func intent(of word: String, in html: String) -> InlinePresentationIntent? {
    let rendered = render(html)
    return rendered.runs.first { String(rendered[$0.range].characters) == word }?
      .inlinePresentationIntent
  }

  @Test func inlineStylesBecomeIntents() {
    let html = "a <b>bold</b> <em>it</em> <del>gone</del> <code>x</code>"
    #expect(text(html) == "a bold it gone x")
    #expect(intent(of: "bold", in: html) == .stronglyEmphasized)
    #expect(intent(of: "it", in: html) == .emphasized)
    #expect(intent(of: "gone", in: html) == .strikethrough)
    #expect(intent(of: "x", in: html) == .code)
  }

  @Test func aMentionIsALinkToThePerson() {
    let html = #"Hi <a href="https://matrix.to/#/@bob:example.org">Bob</a>!"#
    let rendered = render(html)
    #expect(String(rendered.characters) == "Hi Bob!")
    let link = rendered.runs.first { String(rendered[$0.range].characters) == "Bob" }?.link
    #expect(link?.absoluteString == "https://matrix.to/#/@bob:example.org")
  }

  @Test func theReplyFallbackAndScriptsAreDropped() {
    let html =
      "<mx-reply><blockquote>In reply to <b>Alice</b></blockquote></mx-reply>Sure<script>alert(1)</script>"
    #expect(text(html) == "Sure")
  }

  @Test func onlySafeLinksAreKept() {
    let rendered = render(#"<a href="javascript:alert(1)">click</a>"#)
    #expect(String(rendered.characters) == "click")
    #expect(rendered.runs.allSatisfy { $0.link == nil })
  }

  @Test func listsQuotesAndBreaksKeepTheirLines() {
    #expect(text("<ul><li>one</li><li>two</li></ul>") == "• one\n• two")
    #expect(text(#"<ol start="3"><li>a</li><li>b</li></ol>"#) == "3. a\n4. b")
    #expect(text("<blockquote>quoted</blockquote>after") == "│ quoted\nafter")
    #expect(text("<p>first</p><p>second</p>") == "first\nsecond")
    #expect(text("line<br>next<br/>last") == "line\nnext\nlast")
  }

  @Test func whitespaceCollapsesExceptInCodeBlocks() {
    #expect(text("  many \n  spaces  ") == "many spaces")
    #expect(text("<pre><code>let a = 1\n  let b = 2</code></pre>") == "let a = 1\n  let b = 2")
  }

  @Test func entitiesAreDecoded() {
    #expect(text("Tom &amp; Jerry &lt;3 &#39;hi&#39; &#x1F600;") == "Tom & Jerry <3 'hi' 😀")
  }

  @Test func bareAddressesBecomeLinks() {
    let rendered = render("see https://twake.app now")
    let link = rendered.runs.compactMap(\.link).first
    #expect(link?.absoluteString == "https://twake.app")
  }
}

@Suite struct BareLinkTests {
  @Test func aPlainMessageGetsItsAddressesLinked() {
    let text = AttributedString("go to https://twake.app/chat today")
    let linked = MatrixHTML.linkingBareAddresses(text)
    #expect(linked.runs.compactMap(\.link).map(\.absoluteString) == ["https://twake.app/chat"])
  }

  @Test func anExistingLinkIsLeftAlone() {
    var text = AttributedString("https://a.example")
    text.link = URL(string: "https://b.example")
    let linked = MatrixHTML.linkingBareAddresses(text)
    #expect(linked.runs.first?.link?.absoluteString == "https://b.example")
  }
}
