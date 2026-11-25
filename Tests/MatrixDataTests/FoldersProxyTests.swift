import Domain
import Foundation
import Testing

@testable import MatrixData

struct FoldersProxyTests {
  @Test func oneFilteredSyncAsksOnlyForTheFoldersAndTheRoomTags() throws {
    let path = try #require(FoldersProxy.syncPath())
    #expect(path.hasPrefix("sync?timeout=0&filter="))
    let encoded = String(path.dropFirst("sync?timeout=0&filter=".count))
    let json = try #require(encoded.removingPercentEncoding)
    let filter = try #require(
      try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let room = try #require(filter["room"] as? [String: Any])
    #expect((room["timeline"] as? [String: Int])?["limit"] == 0)
    #expect((room["state"] as? [String: [String]])?["types"] == [])
    #expect((room["account_data"] as? [String: [String]])?["types"] == ["m.tag"])
    #expect(
      (filter["account_data"] as? [String: [String]])?["types"] == ["app.twake.chat.folders"])
  }

  @Test func aTagIsOneEncodedPathSegment() {
    #expect(
      FoldersProxy.tagPath(userId: "@me:example.org", roomId: "!r:example.org", tag: "u.My work")
        == "user/%40me%3Aexample%2Eorg/rooms/%21r%3Aexample%2Eorg/tags/u%2EMy%20work")
  }
}
