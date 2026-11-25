import Testing

@testable import Domain

@Suite struct EmojiShortcodeTests {
  @Test func smiSuggestsTheSmile() {
    let shortcodes = EmojiShortcode.suggestions(for: ":smi").map(\.shortcode)
    #expect(shortcodes.prefix(2) == ["smiley", "smile"])
    #expect(shortcodes.contains("sweat_smile"))
    #expect(shortcodes.firstIndex(of: "sweat_smile")! > 1)
  }

  @Test func theNamedEmojiComesFirst() {
    #expect(
      EmojiShortcode.matching("smile").first == EmojiShortcode(shortcode: "smile", emoji: "😄"))
  }

  @Test func ignoresTheCaseAndOffersEightAtMost() {
    #expect(EmojiShortcode.matching("SMILE").first?.emoji == "😄")
    #expect(EmojiShortcode.matching("e").count == EmojiShortcode.limit)
    #expect(EmojiShortcode.limit == 8)
  }

  @Test func offersNothingForAnUnknownNameOrAnEmptyQuery() {
    #expect(EmojiShortcode.matching("zzz").isEmpty)
    #expect(EmojiShortcode.matching("").isEmpty)
  }

  @Test func findsTheQueryAtTheStartOrAfterASpace() {
    #expect(EmojiShortcode.query(in: ":sm") == "sm")
    #expect(EmojiShortcode.query(in: "hi :smi") == "smi")
    #expect(EmojiShortcode.query(in: "line\n:thu") == "thu")
    #expect(EmojiShortcode.query(in: ":s") == "s")
  }

  @Test func aTimeALinkALoneColonOrADigitOfferNothing() {
    #expect(EmojiShortcode.query(in: "at 12:30") == nil)
    #expect(EmojiShortcode.query(in: "see http://x") == nil)
    #expect(EmojiShortcode.query(in: "hi :") == nil)
    #expect(EmojiShortcode.query(in: ":1") == nil)
    #expect(EmojiShortcode.query(in: ":sm ") == nil)
    #expect(EmojiShortcode.query(in: "word:sm") == nil)
  }

  @Test func aFencedCodeBlockOffersNothing() {
    #expect(EmojiShortcode.query(in: "```\n:smi") == nil)
    #expect(EmojiShortcode.query(in: "```\ncode\n```\n:smi") == "smi")
  }

  @Test func pickingReplacesTheShortcodeWithTheEmoji() {
    #expect(EmojiShortcode.replacingQuery(in: "hi :smi", with: "😄") == "hi 😄")
    #expect(EmojiShortcode.replacingQuery(in: ":thumbsup", with: "👍") == "👍")
    #expect(EmojiShortcode.replacingQuery(in: "at 12:30", with: "😄") == "at 12:30")
  }

  @Test func everyShortcodeIsOnceInTheTableAndCanBeTyped() {
    let shortcodes = EmojiShortcode.all.map(\.shortcode)
    #expect(Set(shortcodes).count == shortcodes.count)
    for shortcode in shortcodes {
      #expect(EmojiShortcode.query(in: ":" + shortcode) == shortcode)
    }
  }
}
