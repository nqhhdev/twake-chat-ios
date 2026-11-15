import Domain
import Foundation
import Testing

@testable import MatrixData

struct BroadcastBodyTests {
  private func powerLevels(_ body: [String: Any]) -> [String: Any] {
    body["power_level_content_override"] as? [String: Any] ?? [:]
  }

  private func events(_ body: [String: Any]) -> [String: Int] {
    powerLevels(body)["events"] as? [String: Int] ?? [:]
  }

  private func state(_ body: [String: Any], _ type: String) -> [String: Any]? {
    (body["initial_state"] as? [[String: Any]])?.first { $0["type"] as? String == type }?["content"]
      as? [String: Any]
  }

  @Test func anOpenBroadcastIsAPublicPageWithAnAddressAndAReadableHistory() {
    let draft = BroadcastDraft(
      name: " News ", topic: "What is new", access: .open, slug: "news", allowsReactions: true)
    let body = PeopleProxy.broadcastBody(draft, inviting: [])

    #expect((body["creation_content"] as? [String: String])?["type"] == "app.twake.chat.page")
    #expect(body["name"] as? String == "News")
    #expect(body["topic"] as? String == "What is new")
    #expect(body["preset"] as? String == "public_chat")
    #expect(body["visibility"] as? String == "public")
    #expect(body["room_alias_name"] as? String == "news")
    #expect(powerLevels(body)["events_default"] as? Int == 50)
    #expect(events(body)["m.reaction"] == 0)
    #expect(events(body)["m.room.power_levels"] == 100)
    #expect(
      state(body, "m.room.history_visibility")?["history_visibility"] as? String == "world_readable"
    )
    #expect(state(body, "m.room.encryption") == nil)
  }

  @Test func aBroadcastOnApprovalKnocksAndOneOnInvitationIsPrivateAndEncrypted() {
    let approval = PeopleProxy.broadcastBody(
      BroadcastDraft(name: "Team", access: .approval, allowsReactions: false), inviting: ["@a:x"])
    #expect(state(approval, "m.room.join_rules")?["join_rule"] as? String == "knock")
    #expect(approval["visibility"] as? String == "public")
    #expect(approval["room_alias_name"] == nil)
    #expect(approval["topic"] == nil)
    #expect(events(approval)["m.reaction"] == nil)
    #expect(approval["invite"] as? [String] == ["@a:x"])

    let invitation = PeopleProxy.broadcastBody(
      BroadcastDraft(name: "Board", access: .invitation), inviting: [])
    #expect(invitation["visibility"] as? String == "private")
    #expect(
      state(invitation, "m.room.encryption")?["algorithm"] as? String == "m.megolm.v1.aes-sha2")
  }
}

struct ContactsVisibilityURLTests {
  @Test func theVisibilityOfAUserIsUnderTheirMatrixId() {
    let url = TwakeContactLookup.visibilityURL(
      "@alice:example.org", tom: URL(string: "https://tom.example.org/")!)
    #expect(
      url.absoluteString
        == "https://tom.example.org/_twake/v1/user_info/@alice:example.org/visibility")
  }
}
