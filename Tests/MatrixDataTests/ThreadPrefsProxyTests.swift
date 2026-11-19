import Testing

@testable import MatrixData

/// The mute rule of a thread matches the one the web client writes (`MatrixAccountPrefs.saveThreadPref`), so the server
/// and every client stay silent for it (ADR 0023).
struct ThreadPrefsProxyTests {
  @Test func theMuteRuleMatchesTheRoomAThreadRelationAndItsRoot() {
    #expect(
      ThreadPrefsProxy.muteConditions(roomId: "!room:x", threadId: "$root:x") == [
        .eventMatch(key: "room_id", pattern: "!room:x"),
        .eventPropertyIs(key: "content.m\\.relates_to.rel_type", value: .string(value: "m.thread")),
        .eventPropertyIs(key: "content.m\\.relates_to.event_id", value: .string(value: "$root:x")),
      ])
  }
}
