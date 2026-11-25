import Domain
import RoomTestSupport
import Testing

@testable import Room

@MainActor
struct EmojiSuggestionsTests {
  private func viewModel() -> RoomViewModel {
    RoomViewModel(
      roomId: "!room:example.org", roomName: "Team", repository: FakeTimelineRepository(),
      media: FakeMediaRepository())
  }

  @Test func aShortcodeSuggestsEmojisAndPickingOneReplacesIt() throws {
    let viewModel = viewModel()
    viewModel.draft = "hello :smi"
    let smile = try #require(viewModel.emojiSuggestions.first { $0.shortcode == "smile" })
    #expect(smile.emoji == "😄")
    viewModel.pickEmoji(smile)
    #expect(viewModel.draft == "hello 😄")
    #expect(viewModel.emojiSuggestions.isEmpty)
  }

  @Test func aTimeSuggestsNothing() {
    let viewModel = viewModel()
    viewModel.draft = "at 12:30"
    #expect(viewModel.emojiSuggestions.isEmpty)
  }
}
