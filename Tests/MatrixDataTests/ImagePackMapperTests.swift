import Domain
import Foundation
import Testing

@testable import MatrixData

struct ImagePackMapperTests {
  private let source: (String) -> String? = { "source:" + $0 }

  private let content: [String: Any] = [
    "pack": ["display_name": "Cats", "avatar_url": "mxc://example.org/avatar"],
    "images": [
      "happy": [
        "url": "mxc://example.org/happy", "body": "Happy cat",
        "info": ["w": 256, "h": 128, "mimetype": "image/png", "size": 1234],
      ],
      "emote": ["url": "mxc://example.org/emote", "usage": ["emoticon"]],
      "both": ["url": "mxc://example.org/both", "usage": ["emoticon", "sticker"]],
      "web": ["url": "https://example.org/web.png"],
    ],
  ]

  @Test func aPackKeepsItsStickersWithTheirSizeAndName() throws {
    let mapped = try #require(
      ImagePackMapper.pack(id: "user", content: content, fallbackName: "Mine", source: source))
    #expect(mapped.name == "Cats")
    #expect(mapped.avatar?.source == "source:mxc://example.org/avatar")
    #expect(mapped.stickers.map(\.id) == ["user/both", "user/happy"])
    let happy = mapped.stickers[1]
    #expect(happy.body == "Happy cat")
    #expect(happy.url == "mxc://example.org/happy")
    #expect(
      happy.media
        == MediaReference(
          source: "source:mxc://example.org/happy", mimeType: "image/png", size: 1234, width: 256,
          height: 128))
    #expect(mapped.stickers[0].body == "both")
  }

  @Test func aPackForEmoticonsOnlyOffersNoSticker() {
    let emotes: [String: Any] = [
      "pack": ["usage": ["emoticon"]],
      "images": ["a": ["url": "mxc://example.org/a"]],
    ]
    #expect(
      ImagePackMapper.pack(id: "r", content: emotes, fallbackName: "R", source: source) == nil)
    let named: [String: Any] = ["images": ["a": ["url": "mxc://example.org/a"]]]
    #expect(
      ImagePackMapper.pack(id: "r", content: named, fallbackName: "Room", source: source)?.name
        == "Room")
  }

  @Test func theRoomsOfOtherPacksAreListedOncePerStateKey() {
    let rooms = ImagePackMapper.packRooms([
      "rooms": ["!b:example.org": ["": [:]], "!a:example.org": ["cats": [:], "dogs": [:]]]
    ])
    #expect(rooms.map(\.roomId) == ["!a:example.org", "!a:example.org", "!b:example.org"])
    #expect(rooms.map(\.stateKey) == ["cats", "dogs", ""])
  }

  @Test func accountDataIsReadAsAnEventOrAsItsContent() {
    let event = #"{"type":"im.ponies.user_emotes","content":{"images":{}}}"#
    #expect(ImagePackMapper.eventContent(event)?["images"] != nil)
    #expect(ImagePackMapper.eventContent(#"{"images":{}}"#)?["images"] != nil)
    #expect(ImagePackMapper.eventContent(nil) == nil)
  }

  @Test func aStickerIsSentWithItsUrlAndInfoAndIntoTheThread() throws {
    let sticker = Sticker(
      id: "user/happy", body: "Happy cat", url: "mxc://example.org/happy",
      media: MediaReference(source: "", mimeType: "image/png", size: 10, width: 2, height: 3))
    let plain = ImagePackMapper.stickerContent(sticker, threadRoot: nil)
    #expect(plain["body"] as? String == "Happy cat")
    #expect(plain["url"] as? String == "mxc://example.org/happy")
    let info = try #require(plain["info"] as? [String: Any])
    #expect(info["w"] as? Int == 2)
    #expect(info["h"] as? Int == 3)
    #expect(info["mimetype"] as? String == "image/png")
    #expect(info["size"] as? Int == 10)
    #expect(plain["m.relates_to"] == nil)
    let threaded = ImagePackMapper.stickerContent(sticker, threadRoot: "$root")
    let relation = try #require(threaded["m.relates_to"] as? [String: Any])
    #expect(relation["rel_type"] as? String == "m.thread")
    #expect(relation["event_id"] as? String == "$root")
    #expect(relation["is_falling_back"] as? Bool == true)
  }
}

struct ImagePackEmoteTests {
  private let source: (String) -> String? = { "source:" + $0 }

  @Test func emoticonsAreTheImagesForEmotesWithAValidShortcode() {
    let content: [String: Any] = [
      "images": [
        "cat": ["url": "mxc://example.org/cat", "info": ["w": 64, "h": 64]],
        "sticker_only": ["url": "mxc://example.org/s", "usage": ["sticker"]],
        "bad code": ["url": "mxc://example.org/b"],
        "web": ["url": "https://example.org/w.png"],
      ]
    ]
    let emotes = ImagePackMapper.emotes(content: content, source: source)
    #expect(emotes.map(\.shortcode) == ["cat"])
    #expect(emotes.first?.url == "mxc://example.org/cat")
    #expect(emotes.first?.media.width == 64)
  }

  @Test func aStickerPackGivesNoEmote() {
    let content: [String: Any] = [
      "pack": ["usage": ["sticker"]], "images": ["a": ["url": "mxc://example.org/a"]],
    ]
    #expect(ImagePackMapper.emotes(content: content, source: source).isEmpty)
  }
}
