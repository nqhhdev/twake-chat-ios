import Domain
import Foundation
import RoomTestSupport
import Testing

@testable import Room

@MainActor
struct EmoteSuggestionTests {
  private let cat = Emote(
    shortcode: "cat", url: "mxc://example.org/cat", media: MediaReference(source: "s"))
  private let catJam = Emote(
    shortcode: "catjam", url: "mxc://example.org/jam", media: MediaReference(source: "s"))

  private func viewModel() async -> (RoomViewModel, FakeTimelineRepository) {
    let repository = FakeTimelineRepository()
    repository.emoteList = [cat, catJam]
    let room = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: repository, media: FakeMediaRepository())
    await room.loadEmotes()
    return (room, repository)
  }

  @Test func typingAShortcodeOffersThePacksEmotes() async {
    let (room, _) = await viewModel()
    #expect(room.emoteSuggestions.isEmpty)
    room.draft = "look :ca"
    #expect(room.emoteSuggestions.map(\.shortcode) == ["cat", "catjam"])
    room.draft = "look :dog"
    #expect(room.emoteSuggestions.isEmpty)
  }

  @Test func pickingAnEmoteWritesItsShortcode() async {
    let (room, _) = await viewModel()
    room.draft = "look :ca"
    room.pickEmote(cat)
    #expect(room.draft == "look :cat: ")
  }

  @Test func theEmotesOfAMessageAreLoadedOnceEach() {
    let text = MatrixHTML.attributedString(
      from:
        #"<img data-mx-emoticon src="mxc://a/1" alt=":a:"> <img data-mx-emoticon src="mxc://a/1" alt=":a:"> <img data-mx-emoticon src="mxc://a/2" alt=":b:">"#
    )
    #expect(RoomViewModel.emoteSources(in: text) == ["mxc://a/1", "mxc://a/2"])
  }
}
