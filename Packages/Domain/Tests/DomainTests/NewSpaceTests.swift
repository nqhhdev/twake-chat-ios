import Foundation
import Testing

@testable import Domain

struct NewSpaceTests {
  private func json(_ object: [String: Any]) throws -> [String: Any] {
    let data = try JSONSerialization.data(withJSONObject: object)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  @Test func aPrivateSpaceIsAnMSpaceInTheClearWithTheWebsPowerLevels() throws {
    let body = try json(
      NewSpace(name: "  Design  ", topic: "Our team").createRoomBody(ownServer: "example.org"))
    #expect(body["name"] as? String == "Design")
    #expect(body["topic"] as? String == "Our team")
    #expect(body["preset"] as? String == "private_chat")
    #expect(body["visibility"] == nil)
    #expect((body["creation_content"] as? [String: Any])?["type"] as? String == "m.space")
    let overrides = try #require(body["power_level_content_override"] as? [String: Any])
    let events = try #require(overrides["events"] as? [String: Int])
    #expect(events["org.matrix.msc3401.call.member"] == 0)
    #expect(events["m.poll.response"] == 0)
    #expect(events["app.twake.chat.public_page"] == 100)
    #expect((body["initial_state"] as? [Any])?.isEmpty == true)
    #expect(body["initial_state"] != nil)
  }

  @Test func aPublicSpaceIsListedInTheDirectory() throws {
    let body = try json(NewSpace(name: "Open", isPublic: true).createRoomBody(ownServer: nil))
    #expect(body["preset"] as? String == "public_chat")
    #expect(body["visibility"] as? String == "public")
    #expect(body["topic"] == nil)
  }

  @Test func aSubSpaceNamesItsParentAndLetsItsMembersJoin() throws {
    let body = try json(
      NewSpace(name: "Sub", parentId: "!parent:other.org").createRoomBody(ownServer: "example.org"))
    let state = try #require(body["initial_state"] as? [[String: Any]])
    #expect(state.count == 2)
    #expect(state[0]["type"] as? String == "m.space.parent")
    #expect(state[0]["state_key"] as? String == "!parent:other.org")
    let parent = try #require(state[0]["content"] as? [String: Any])
    #expect(parent["via"] as? [String] == ["other.org", "example.org"])
    #expect(parent["canonical"] as? Bool == true)
    #expect(state[1]["type"] as? String == "m.room.join_rules")
    let rule = try #require(state[1]["content"] as? [String: Any])
    #expect(rule["join_rule"] as? String == "restricted")
    let allow = try #require(rule["allow"] as? [[String: String]])
    #expect(allow == [["type": "m.room_membership", "room_id": "!parent:other.org"]])
  }

  @Test func aPublicSubSpaceKeepsThePublicJoinRule() throws {
    let body = try json(
      NewSpace(name: "Sub", isPublic: true, parentId: "!p:example.org").createRoomBody(
        ownServer: "example.org"))
    let state = try #require(body["initial_state"] as? [[String: Any]])
    #expect(state.map { $0["type"] as? String } == ["m.space.parent"])
    #expect(
      (state[0]["content"] as? [String: Any])?["via"] as? [String] == ["example.org"])
  }

  @Test func aPictureIsSetAtCreation() throws {
    let body = try json(
      NewSpace(name: "Pic").createRoomBody(ownServer: nil, avatarURL: "mxc://example.org/abc"))
    let state = try #require(body["initial_state"] as? [[String: Any]])
    #expect(state.first?["type"] as? String == "m.room.avatar")
    #expect((state.first?["content"] as? [String: String])?["url"] == "mxc://example.org/abc")
  }

  @Test func theParentListsItsChildThroughTheServersOfBoth() throws {
    let content = try json(
      NewSpace.childContent(childId: "!child:other.org", ownServer: "example.org"))
    #expect(content["via"] as? [String] == ["other.org", "example.org"])
  }

  @Test func aSpaceNeedsAName() {
    #expect(!NewSpace(name: "   ").canCreate)
    #expect(NewSpace(name: "A").canCreate)
  }
}
