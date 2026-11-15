import Domain
import Foundation
import Testing

struct PollTests {
  private func poll(
    max: Int = 1, disclosed: Bool = true, ended: Bool = false, own: Set<String> = []
  ) -> Poll {
    Poll(
      question: "Lunch?",
      answers: [
        .init(id: "a", text: "Pizza", voterIds: ["@x:s", "@y:s"]),
        .init(id: "b", text: "Sushi", voterIds: ["@x:s"]),
        .init(id: "c", text: "Salad"),
      ],
      maxSelections: max, isDisclosed: disclosed, isEnded: ended, ownAnswerIds: own)
  }

  @Test func eachVoterCountsOnceAndSharesAreOfVoters() {
    let poll = poll()
    #expect(poll.voterCount == 2)
    #expect(poll.share(of: poll.answers[0]) == 1)
    #expect(poll.share(of: poll.answers[1]) == 0.5)
  }

  @Test func resultsShowAfterVotingInADisclosedPollOrAtTheEnd() {
    #expect(!poll().showsResults)
    #expect(poll(own: ["a"]).showsResults)
    #expect(!poll(disclosed: false, own: ["a"]).showsResults)
    #expect(poll(disclosed: false, ended: true).showsResults)
  }

  @Test func theWinnersAreKnownOnlyOnceEnded() {
    #expect(poll().winningAnswerIds.isEmpty)
    #expect(poll(ended: true).winningAnswerIds == ["a"])
  }

  @Test func aSingleChoiceSwapsTheVote() {
    #expect(poll(own: ["a"]).selection(tapping: "b") == ["b"])
  }

  @Test func aMultipleChoiceAddsRemovesAndDropsTheOldestWhenFull() {
    #expect(poll(max: 2, own: ["a"]).selection(tapping: "b") == ["a", "b"])
    #expect(poll(max: 2, own: ["a", "b"]).selection(tapping: "a") == ["b"])
    #expect(poll(max: 2, own: ["a", "b"]).selection(tapping: "c") == ["b", "c"])
  }

  @Test func aDraftNeedsAQuestionAndTwoAnswers() {
    var draft = PollDraft(question: " ", answers: ["Yes", "No"])
    #expect(!draft.canSend)
    draft.question = "Ok?"
    #expect(draft.canSend)
    draft.answers = ["Yes", "  ", ""]
    #expect(draft.cleanAnswers == ["Yes"])
    #expect(!draft.canSend)
  }
}

struct SavedMessagesTests {
  @Test func readsTheWebFormatAndSkipsBadEntries() {
    let json = Data(
      #"{"messages":[{"roomId":"!a:s","eventId":"$1","savedAt":20},{"roomId":"!a:s"}]}"#.utf8)
    #expect(
      SavedMessages.refs(fromJSON: json) == [SavedRef(roomId: "!a:s", eventId: "$1", savedAt: 20)])
    #expect(SavedMessages.refs(fromJSON: nil).isEmpty)
  }

  @Test func savingPutsTheNewestFirstAndForgettingRemovesIt() {
    let old = SavedRef(roomId: "!a:s", eventId: "$1", savedAt: 1)
    let now = Date(timeIntervalSince1970: 2)
    let saved = SavedMessages.with([old], roomId: "!b:s", eventId: "$2", saved: true, now: now)
    #expect(saved.map(\.eventId) == ["$2", "$1"])
    #expect(saved.first?.savedAt == 2000)
    #expect(
      SavedMessages.with(saved, roomId: "!a:s", eventId: "$1", saved: false).map(\.eventId) == [
        "$2"
      ])
    #expect(SavedMessages.refs(fromJSON: SavedMessages.json(saved)) == saved)
  }
}

struct RoomArchiveTests {
  @Test func leavingAddsTheRoomFirstAndKeepsWhatOthersWrote() throws {
    let web = Data(
      #"{"rooms":[{"roomId":"!a:s","name":"A","isDirect":false,"leftAt":1,"ban":{"by":"@x:s","reason":null}}]}"#
        .utf8)
    let entry = ArchivedRoomEntry(roomId: "!b:s", name: "B", isDirect: true, leftAt: 5)
    let updated = try #require(RoomArchive.json(updating: web, roomId: "!b:s", with: entry))
    #expect(RoomArchive.entries(fromJSON: updated).map(\.roomId) == ["!b:s", "!a:s"])
    let text = String(decoding: updated, as: UTF8.self)
    #expect(text.contains("\"ban\""))
    let dropped = RoomArchive.json(updating: updated, roomId: "!a:s", with: nil)
    #expect(RoomArchive.entries(fromJSON: dropped) == [entry])
  }
}

struct BotCommandTests {
  private let gif = BotCommand(
    botUserId: "@bot:s", syntax: "gif {search} {words...}", description: "A GIF")

  @Test func theSyntaxGivesTheNameAndArguments() {
    #expect(gif.name == "gif")
    #expect(gif.argumentNames == ["search", "words"])
    #expect(gif.isLastArgumentVariadic)
  }

  @Test func theContentNamesTheCommandAndItsArguments() throws {
    let content = gif.content(for: "/gif cat very funny")
    let command = try #require(content["org.matrix.msc4332.command"] as? [String: Any])
    let arguments = try #require(command["arguments"] as? [String: Any])
    #expect(command["syntax"] as? String == "gif {search} {words...}")
    #expect(arguments["search"] as? String == "cat")
    #expect(arguments["words..."] as? [String] == ["very", "funny"])
    #expect(content["body"] as? String == "/gif cat very funny")
  }

  @Test func typingASlashSuggestsAndFindsCommands() {
    #expect(BotCommand.matching("/g", in: [gif]) == [gif])
    #expect(BotCommand.matching("/g x", in: [gif]).isEmpty)
    #expect(BotCommand.command(for: "/GIF cat", in: [gif]) == gif)
    #expect(BotCommand.command(for: "hello", in: [gif]) == nil)
  }

  @Test func announcedCommandsAreRead() {
    let content: [String: Any] = [
      "commands": [
        ["syntax": "help", "description": ["m.text": [["body": "Shows help"]]]], ["nosyntax": 1],
      ]
    ]
    let commands = BotCommand.commands(botUserId: "@bot:s", content: content)
    #expect(commands.map(\.name) == ["help"])
    #expect(commands.first?.description == "Shows help")
  }
}

struct LinkedAddressTests {
  @Test func emailsAndPhonesAreReadAndOtherMediaLeftOut() {
    let json = Data(
      #"{"threepids":[{"medium":"email","address":"a@b.org"},{"medium":"msisdn","address":"33612345678"},{"medium":"x","address":"y"}]}"#
        .utf8)
    #expect(
      LinkedAddress.addresses(fromJSON: json) == [
        LinkedAddress(kind: .email, address: "a@b.org"),
        LinkedAddress(kind: .phone, address: "+33612345678"),
      ])
  }
}

struct MessageVersionTests {
  @Test func theOriginalComesFirstThenTheEditsByDate() {
    let original = Data(
      #"{"event_id":"$o","origin_server_ts":1000,"content":{"body":"helo"}}"#.utf8)
    let relations = Data(
      #"{"chunk":[{"event_id":"$2","origin_server_ts":3000,"content":{"body":"* hello!","m.new_content":{"body":"hello!"}}},{"event_id":"$1","origin_server_ts":2000,"content":{"m.new_content":{"body":"hello"}}}]}"#
        .utf8)
    let versions = MessageVersion.versions(original: original, relations: relations)
    #expect(versions.map(\.text) == ["helo", "hello", "hello!"])
    #expect(MessageVersion.versions(original: nil, relations: nil).isEmpty)
  }
}

@Suite struct BroadcastDraftTests {
  @Test func aNameGivesALowercaseAddressWithDashes() {
    #expect(BroadcastDraft.slug(from: "Équipe Produit — 2026!") == "equipe-produit-2026")
    #expect(BroadcastDraft.slug(from: "  ") == "")
  }

  @Test func anOpenBroadcastNeedsAValidAddress() {
    var draft = BroadcastDraft(name: "News", access: .open, slug: "News")
    #expect(!draft.canCreate)
    draft.slug = "news-2026"
    #expect(draft.canCreate)
    draft.slug = "-news"
    #expect(!draft.canCreate)
    draft.access = .invitation
    #expect(draft.canCreate)
    draft.name = " "
    #expect(!draft.canCreate)
  }
}

@Suite struct PresenceTests {
  @Test func theHeaderLineIsTheStatusThenOnlineThenTheLastActivity() {
    #expect(Presence(isOnline: true, statusMessage: "In a meeting").line == "In a meeting")
    #expect(Presence(isOnline: true).line == "Online")
    #expect(Presence(isOnline: false, lastActive: 30).line == "Active just now")
    #expect(Presence(isOnline: false, lastActive: 5 * 60).line == "Active 5 min ago")
    #expect(Presence(isOnline: false, lastActive: 3 * 3600).line == "Active 3 h ago")
    #expect(Presence(isOnline: false, lastActive: 26 * 3600).line == "Active yesterday")
    #expect(Presence(isOnline: false).line == nil)
  }

  @Test func theServerAnswerIsReadInSeconds() {
    let presence = Presence.from([
      "presence": "online", "currently_active": true, "last_active_ago": 12_000, "status_msg": "",
    ])
    #expect(presence == Presence(isOnline: true, lastActive: 12, statusMessage: nil))
    #expect(!Presence.from(["presence": "online", "last_active_ago": 900_000]).isOnline)
  }
}
