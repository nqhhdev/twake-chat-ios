import RoomTestSupport
import Testing

@testable import Room

struct TextFormattingTests {
  private func apply(_ format: TextFormat, _ text: String, _ selection: Range<Int>) -> FormattedText
  {
    TextFormatting.apply(format, to: text, selection: selection)
  }

  @Test func wrapsTheSelectionInTheMarksOfEachFormat() {
    #expect(
      apply(.bold, "say hi now", 4..<6) == FormattedText(text: "say **hi** now", selection: 6..<8))
    #expect(
      apply(.italic, "say hi now", 4..<6) == FormattedText(text: "say _hi_ now", selection: 5..<7))
    #expect(
      apply(.strike, "say hi now", 4..<6) == FormattedText(text: "say ~~hi~~ now", selection: 6..<8)
    )
    #expect(
      apply(.code, "say hi now", 4..<6) == FormattedText(text: "say `hi` now", selection: 5..<7))
  }

  @Test func leavesTheSpacesAroundTheSelectionOutsideTheMarks() {
    #expect(
      apply(.bold, "say hi now", 3..<7) == FormattedText(text: "say **hi** now", selection: 6..<8))
  }

  @Test func anEmptySelectionWritesBothMarksWithTheCaretBetween() {
    #expect(apply(.bold, "say ", 4..<4) == FormattedText(text: "say ****", selection: 6..<6))
    #expect(apply(.italic, "", 0..<0) == FormattedText(text: "__", selection: 1..<1))
  }

  @Test func aSecondTapTakesTheMarksOffAroundTheSelection() {
    let bold = apply(.bold, "say hi now", 4..<6)
    #expect(
      apply(.bold, bold.text, bold.selection) == FormattedText(text: "say hi now", selection: 4..<6)
    )
  }

  @Test func takesTheMarksOffWhenTheSelectionHoldsThem() {
    #expect(
      apply(.strike, "say ~~hi~~ now", 4..<10)
        == FormattedText(text: "say hi now", selection: 4..<6))
  }

  @Test func formatsCombineOneInsideTheOther() {
    let bold = apply(.bold, "hi", 0..<2)
    #expect(
      apply(.italic, bold.text, bold.selection) == FormattedText(text: "**_hi_**", selection: 3..<5)
    )
  }

  @Test func countsCharactersNotBytes() {
    #expect(apply(.bold, "👋🏽 hi", 0..<1) == FormattedText(text: "**👋🏽** hi", selection: 2..<3))
  }

  @Test func aSelectionPastTheEndIsCut() {
    #expect(apply(.code, "hi", 0..<9) == FormattedText(text: "`hi`", selection: 1..<3))
  }

  @Test func aCodeBlockPutsItsFencesOnLinesOfTheirOwnAndComesOffAgain() {
    let block = apply(.codeBlock, "see let x = 1 ok", 4..<13)
    #expect(block == FormattedText(text: "see \n```\nlet x = 1\n```\n ok", selection: 9..<18))
    #expect(apply(.codeBlock, block.text, block.selection).text == "see \nlet x = 1\n ok")
  }

  @Test func theLinkDialogStartsFromTheSelectionOrTheLinkItIsIn() {
    #expect(
      TextFormatting.linkTarget(in: "go home", selection: 3..<7)
        == LinkTarget(range: 3..<7, text: "home", url: ""))
    #expect(
      TextFormatting.linkTarget(in: "go [home](https://a.org) now", selection: 5..<6)
        == LinkTarget(range: 3..<24, text: "home", url: "https://a.org"))
  }

  @Test func writesTheLinkWithTheCaretAfterIt() {
    let target = LinkTarget(range: 3..<7, text: "home", url: "")
    #expect(
      TextFormatting.link(target, in: "go home", label: "home", url: "https://a.org")
        == FormattedText(text: "go [home](https://a.org)", selection: 24..<24))
    #expect(
      TextFormatting.link(
        LinkTarget(range: 0..<0, text: "", url: ""), in: "", label: " ", url: "https://a.org"
      )
      .text == "[https://a.org](https://a.org)")
  }

  @Test func onlyWebAddressesMakeLinks() {
    #expect(TextFormatting.webAddress(" https://a.org/x ") == "https://a.org/x")
    #expect(TextFormatting.webAddress("www.a.org") == "https://www.a.org")
    #expect(TextFormatting.webAddress("ftp://a.org") == nil)
    #expect(TextFormatting.webAddress("https://a.org/(x)") == nil)
    #expect(TextFormatting.webAddress("hello") == nil)
  }

  @MainActor @Test func theViewModelFormatsTheDraftAndSelectsTheFormattedText() {
    let viewModel = RoomViewModel(
      roomId: "!room:example.org", roomName: "Team", repository: FakeTimelineRepository(),
      media: FakeMediaRepository())
    viewModel.draft = "say hi"
    let start = viewModel.draft.index(viewModel.draft.startIndex, offsetBy: 4)
    let selection = viewModel.format(.bold, selection: start..<viewModel.draft.endIndex)
    #expect(viewModel.draft == "say **hi**")
    #expect(viewModel.draft[selection] == "hi")
    let target = viewModel.linkTarget(selection: selection)
    #expect(viewModel.addLink(target, label: "hi", url: "not a link") == nil)
    #expect(viewModel.draft == "say **hi**")
    _ = viewModel.addLink(target, label: "hi", url: "www.a.org")
    #expect(viewModel.draft == "say **[hi](https://www.a.org)**")
  }
}
