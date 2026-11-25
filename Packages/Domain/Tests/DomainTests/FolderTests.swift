import Foundation
import Testing

@testable import Domain

struct FolderContentTests {
  private func roundTrip(_ object: [String: Any]) throws -> [String: Any] {
    let data = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  @Test func readsTheWebAndFlutterFormat() {
    let folders = FolderContent.read([
      "folders": [
        ["builtin": "unread", "name": " Fresh ", "emoji": "🔥"],
        ["builtin": "spaces", "hidden": true],
        ["builtin": "voice"],
        ["name": "Work", "emoji": "💼", "color": "#1A2B3C", "include": ["direct", "bot", "nope"]],
        ["name": "Clients", "exclude": ["!a:example.org", 3]],
        ["name": "Work"],
        ["name": "  "],
        ["builtin": "unread"],
        "junk",
        ["name": "Bad", "color": "red", "emoji": ""],
      ]
    ])
    #expect(
      folders == [
        Folder(name: "Fresh", builtin: .unread, emoji: "🔥"),
        Folder(name: "", builtin: .spaces, isHidden: true),
        Folder(name: "Work", emoji: "💼", color: "#1A2B3C", include: [.direct, .bot]),
        Folder(name: "Clients", exclude: ["!a:example.org"]),
        Folder(name: "Bad"),
      ])
  }

  @Test func readsNothingFromNothing() {
    #expect(FolderContent.read(nil).isEmpty)
    #expect(FolderContent.read(["folders": "nope"]).isEmpty)
  }

  @Test func writesWithoutEmptyPartsAndKeepsWhatAnotherClientAdded() throws {
    let current: [String: Any] = [
      "version": 2,
      "folders": [
        ["name": "Work", "pinned": true, "emoji": "old"],
        ["builtin": "voice", "name": "Calls"],
        ["builtin": "unread", "sort": "recent"],
      ],
    ]
    let written = try roundTrip(
      FolderContent.write(
        [
          Folder(name: "", builtin: .unread),
          Folder(name: "Work", include: [.group]),
          Folder(name: "", builtin: .spaces, isHidden: true),
        ], current: current))
    #expect(written["version"] as? Int == 2)
    let items = try #require(written["folders"] as? [[String: Any]])
    #expect(items.count == 4)
    #expect(items[0]["builtin"] as? String == "unread")
    #expect(items[0]["sort"] as? String == "recent")
    #expect(items[0]["name"] == nil)
    #expect(items[1]["name"] as? String == "Work")
    #expect(items[1]["pinned"] as? Bool == true)
    #expect(items[1]["emoji"] == nil)
    #expect(items[1]["include"] as? [String] == ["group"])
    #expect(items[1]["exclude"] == nil)
    #expect(items[2]["builtin"] as? String == "spaces")
    #expect(items[2]["hidden"] as? Bool == true)
    #expect(items[3]["builtin"] as? String == "voice")
  }

  @Test func whatIsWrittenReadsBackTheSame() throws {
    let folders = [
      Folder(
        name: "Team", emoji: "👥", color: "#00ff00", include: [.group, .broadcast], exclude: ["!x"]),
      Folder(name: "Mine", builtin: .favourites),
    ]
    let content = try roundTrip(FolderContent.write(folders, current: nil))
    #expect(FolderContent.read(content) == folders)
  }

  @Test func theFoldersOfARoomAreItsUserTags() {
    #expect(
      FolderContent.folderNames(fromTags: ["m.favourite", "u.Work", "u.", "u.Clients"])
        == ["Work", "Clients"])
    #expect(FolderTagChange(roomId: "!r", folderName: "Work", isIn: true).tag == "u.Work")
  }

  @Test func oneSyncGivesTheFoldersAndTheTagsOfEveryRoom() {
    let state = FolderContent.state(fromSync: [
      "account_data": [
        "events": [
          ["type": "m.push_rules", "content": [:]],
          ["type": "app.twake.chat.folders", "content": ["folders": [["name": "Work"]]]],
        ]
      ],
      "rooms": [
        "join": [
          "!a:example.org": [
            "account_data": [
              "events": [
                ["type": "m.tag", "content": ["tags": ["u.Work": [:], "m.favourite": [:]]]]
              ]
            ]
          ],
          "!b:example.org": ["account_data": ["events": []]],
          "!c:example.org": [
            "account_data": ["events": [["type": "m.tag", "content": ["tags": ["u.Old": [:]]]]]]
          ],
        ]
      ],
    ])
    #expect(state.saved == [Folder(name: "Work")])
    #expect(state.roomFolders == ["!a:example.org": ["Work"], "!c:example.org": ["Old"]])
    #expect(state.shown.filter(\.isUser).map(\.name) == ["Work", "Old"])
  }
}

struct FolderRulesTests {
  private func room(
    _ id: String, direct: Bool = false, broadcast: Bool = false, space: Bool = false,
    user: String? = nil
  ) -> RoomSummary {
    RoomSummary(
      id: id, name: id, lastMessageText: nil, lastMessageSender: nil, lastActivity: nil,
      isDirect: direct, isSpace: space, isBroadcast: broadcast, directUserId: user)
  }

  @Test func eachChatHasTheWebsKind() {
    #expect(Folder.chatType(of: room("!d", direct: true, user: "@alice:x")) == .direct)
    #expect(Folder.chatType(of: room("!b", direct: true, user: "@bot_weather:x")) == .bot)
    #expect(Folder.chatType(of: room("!h", direct: true, user: "@hermes_1:x")) == .bot)
    #expect(Folder.chatType(of: room("!p", broadcast: true)) == .broadcast)
    #expect(Folder.chatType(of: room("!g")) == .group)
    #expect(Folder.chatType(of: room("!s", space: true)) == nil)
  }

  @Test func keptOutWinsThenPickedThenItsKind() {
    let folder = Folder(name: "Work", include: [.direct], exclude: ["!out"])
    #expect(folder.contains(room("!dm", direct: true), folders: []))
    #expect(!folder.contains(room("!out", direct: true), folders: ["Work"]))
    #expect(folder.contains(room("!g"), folders: ["Work"]))
    #expect(!folder.contains(room("!g"), folders: ["Other"]))
    #expect(!folder.contains(room("!s", space: true), folders: ["Work"]))
    #expect(!Folder(name: "", builtin: .unread).contains(room("!g"), folders: [""]))
  }

  @Test func theListShowsUnknownBuiltinsThenTheSavedThenTheTaggedByName() {
    let saved = [
      Folder(name: "", builtin: .favourites), Folder(name: "Work"),
      Folder(name: "", builtin: .spaces, isHidden: true),
    ]
    let shown = Folder.list(saved: saved, taggedNames: ["Zed", "Work", "Alpha", "Zed"])
    #expect(
      shown.map(\.id) == [
        "builtin.unread", "builtin.broadcasts", "builtin.directs", "builtin.favourites",
        "folder.Work", "folder.Alpha", "folder.Zed",
      ])
    #expect(
      Folder.withHiddenBuiltins(shown).suffix(1).map(\.id) == ["builtin.spaces"])
    #expect(Folder.withHiddenBuiltins(shown).last?.isHidden == true)
  }

  @Test func savingAFolderTagsPickedChatsAndExcludesUnpickedOnesOfItsKind() {
    let chats = [
      room("!g1"), room("!g2"), room("!d1", direct: true), room("!d2", direct: true),
    ]
    let folder = Folder(name: "Mix", include: [.direct])
    let plan = Folder.planEdit(
      folder: folder, previous: nil, picked: ["!g1", "!d1"], chats: chats, roomFolders: [:])
    #expect(plan.changes == [FolderTagChange(roomId: "!g1", folderName: "Mix", isIn: true)])
    #expect(plan.folder.exclude == ["!d2"])
  }

  @Test func untickingAChatRemovesItsTagAndRenamingMovesEveryTag() {
    let chats = [room("!a"), room("!b")]
    let previous = Folder(name: "Old", exclude: ["!gone"])
    let unticked = Folder.planEdit(
      folder: previous, previous: previous, picked: ["!a"], chats: chats,
      roomFolders: ["!a": ["Old"], "!b": ["Old"]])
    #expect(unticked.changes == [FolderTagChange(roomId: "!b", folderName: "Old", isIn: false)])
    #expect(unticked.folder.exclude == ["!gone"])
    let renamed = Folder.planEdit(
      folder: Folder(name: "New"), previous: previous, picked: ["!a"], chats: chats,
      roomFolders: ["!a": ["Old"]])
    #expect(
      renamed.changes == [
        FolderTagChange(roomId: "!a", folderName: "New", isIn: true),
        FolderTagChange(roomId: "!a", folderName: "Old", isIn: false),
      ])
  }

  @Test func aFolderMovesAmongTheUserFoldersOnly() {
    let folders = [
      Folder(name: "", builtin: .unread), Folder(name: "A"), Folder(name: "", builtin: .spaces),
      Folder(name: "B"), Folder(name: "C"),
    ]
    #expect(
      Folder.moving("folder.A", by: 1, in: folders).map(\.id) == [
        "builtin.unread", "folder.B", "builtin.spaces", "folder.A", "folder.C",
      ])
    #expect(Folder.moving("folder.A", by: -1, in: folders) == folders)
    #expect(Folder.moving("folder.C", by: 1, in: folders) == folders)
    #expect(Folder.moving("folder.Nope", by: 1, in: folders) == folders)
  }
}
