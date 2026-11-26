import Domain
import Foundation
import Intents
import Testing

@testable import TwakeChat

@MainActor
struct ShareSuggestionsTests {
  @MainActor
  final class Recorder {
    var donated: [INInteraction] = []
    var forgotten: [String] = []
    var forgotAll = 0

    var system: ShareSuggestions.System {
      ShareSuggestions.System(
        donate: { self.donated.append($0) },
        forget: { self.forgotten.append($0) },
        forgetAll: { self.forgotAll += 1 })
    }
  }

  actor CountingMedia: MediaRepository {
    var thumbnails = 0
    let fails: Bool

    init(fails: Bool = false) {
      self.fails = fails
    }

    func thumbnail(_ media: MediaReference, width: Int, height: Int) async throws(MediaError)
      -> Data
    {
      thumbnails += 1
      if fails { throw .downloadFailed }
      return Data([1, 2, 3])
    }

    func content(_ media: MediaReference) async throws(MediaError) -> Data {
      throw .downloadFailed
    }

    func file(_ media: MediaReference, filename: String) async throws(MediaError) -> URL {
      throw .downloadFailed
    }
  }

  @Test func theIntentNamesTheChatAndHoldsNoMessage() {
    let intent = ShareSuggestions.intent(roomId: "!a:x", name: "Team", image: nil)
    #expect(intent.conversationIdentifier == "!a:x")
    #expect(intent.speakableGroupName?.spokenPhrase == "Team")
    #expect(intent.content == nil)
    #expect(intent.recipients == nil)
    #expect(intent.attachments == nil)
    #expect(intent.sender == nil)
  }

  @Test func sendingInAChatDonatesItAsOutgoing() async throws {
    let recorder = Recorder()
    let suggestions = ShareSuggestions(system: recorder.system)
    await suggestions.suggest(roomId: "!a:x", name: "Team", avatar: nil, media: CountingMedia())
    let interaction = try #require(recorder.donated.first)
    #expect(interaction.direction == .outgoing)
    #expect(interaction.groupIdentifier == "!a:x")
    let intent = try #require(interaction.intent as? INSendMessageIntent)
    #expect(intent.conversationIdentifier == "!a:x")
    #expect(intent.content == nil)
  }

  @Test func theChatPictureIsLoadedOnce() async throws {
    let recorder = Recorder()
    let suggestions = ShareSuggestions(system: recorder.system)
    let media = CountingMedia()
    let avatar = MediaReference(source: "mxc://x/a")
    await suggestions.suggest(roomId: "!a:x", name: "Team", avatar: avatar, media: media)
    await suggestions.suggest(roomId: "!a:x", name: "Team", avatar: avatar, media: media)
    #expect(await media.thumbnails == 1)
    let intent = try #require(recorder.donated.last?.intent as? INSendMessageIntent)
    #expect(intent.image(forParameterNamed: \.speakableGroupName) != nil)
  }

  @Test func aPictureThatFailsToLoadStillDonatesTheChat() async throws {
    let recorder = Recorder()
    let suggestions = ShareSuggestions(system: recorder.system)
    let avatar = MediaReference(source: "mxc://x/a")
    await suggestions.suggest(
      roomId: "!a:x", name: "Team", avatar: avatar, media: CountingMedia(fails: true))
    let intent = try #require(recorder.donated.first?.intent as? INSendMessageIntent)
    #expect(intent.image(forParameterNamed: \.speakableGroupName) == nil)
  }

  @Test func leavingAChatOrSigningOutForgetsTheSuggestions() async {
    let recorder = Recorder()
    let suggestions = ShareSuggestions(system: recorder.system)
    let media = CountingMedia()
    let avatar = MediaReference(source: "mxc://x/a")
    await suggestions.suggest(roomId: "!a:x", name: "Team", avatar: avatar, media: media)
    suggestions.forget("!a:x")
    #expect(recorder.forgotten == ["!a:x"])
    suggestions.forgetAll()
    #expect(recorder.forgotAll == 1)
    await suggestions.suggest(roomId: "!a:x", name: "Team", avatar: avatar, media: media)
    #expect(await media.thumbnails == 2)
  }

  @Test func theIntentNamesItsAccountAsTheUser() throws {
    let intent = ShareSuggestions.intent(
      roomId: "!a:x", name: "Team", image: nil, accountUserId: "@me:x")
    let sender = try #require(intent.sender)
    #expect(sender.isMe)
    #expect(sender.customIdentifier == "@me:x")
    #expect(intent.conversationIdentifier == "!a:x")
    #expect(intent.serviceName == nil)
  }
}
