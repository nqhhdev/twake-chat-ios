import DesignSystem
import Foundation
import Testing
import UIKit

@MainActor
struct SelectableTextTests {
  private func font(of text: NSAttributedString, at word: String) -> UIFont? {
    let location = (text.string as NSString).range(of: word).location
    return text.attribute(.font, at: location, effectiveRange: nil) as? UIFont
  }

  @Test func keepsTheWordsAndLinks() throws {
    var source = AttributedString("open example.com now")
    let url = try #require(URL(string: "https://example.com"))
    source[try #require(source.range(of: "example.com"))].link = url
    let text = SelectableText.attributed(source)
    #expect(text.string == "open example.com now")
    let location = (text.string as NSString).range(of: "example.com").location
    #expect(text.attribute(.link, at: location, effectiveRange: nil) as? URL == url)
    #expect(text.attribute(.link, at: 0, effectiveRange: nil) == nil)
  }

  @Test func keepsBoldItalicCodeAndStrikethrough() throws {
    var source = AttributedString("plain bold italic code gone")
    source[try #require(source.range(of: "bold"))].inlinePresentationIntent = .stronglyEmphasized
    source[try #require(source.range(of: "italic"))].inlinePresentationIntent = .emphasized
    source[try #require(source.range(of: "code"))].inlinePresentationIntent = .code
    source[try #require(source.range(of: "gone"))].inlinePresentationIntent = .strikethrough
    let text = SelectableText.attributed(source)
    let traits = { (word: String) in
      self.font(of: text, at: word)?.fontDescriptor.symbolicTraits ?? []
    }
    #expect(!traits("plain").contains(.traitBold))
    #expect(traits("bold").contains(.traitBold))
    #expect(traits("italic").contains(.traitItalic))
    #expect(traits("code").contains(.traitMonoSpace))
    let gone = (text.string as NSString).range(of: "gone").location
    #expect(
      text.attribute(.strikethroughStyle, at: gone, effectiveRange: nil) as? Int
        == NSUnderlineStyle.single.rawValue)
  }
}
