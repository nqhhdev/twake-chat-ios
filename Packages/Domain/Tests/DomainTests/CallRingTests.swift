import Foundation
import Testing

@testable import Domain

struct CallRingTests {
  private let now = Date(timeIntervalSince1970: 1_000_000)

  private func ring(expiresIn seconds: TimeInterval, account: String? = "@me:a") -> CallRing {
    CallRing(
      roomId: "!r:a", eventId: "$ring", roomName: "Team", isVoice: true,
      expiresAt: now.addingTimeInterval(seconds), accountUserId: account)
  }

  @Test func aRingRingsUntilItExpires() {
    #expect(ring(expiresIn: 30).isRinging(at: now))
    #expect(!ring(expiresIn: 0).isRinging(at: now))
    #expect(!ring(expiresIn: -5).isRinging(at: now))
  }

  @Test func aRingSetToExpireTooFarAheadDoesNotRing() {
    #expect(ring(expiresIn: CallRing.maximumRingTime).isRinging(at: now))
    #expect(!ring(expiresIn: CallRing.maximumRingTime + 1).isRinging(at: now))
  }

  @Test func thePayloadComesBackAsTheSameRing() throws {
    let original = ring(expiresIn: 30)
    let decoded = try #require(CallRing(payload: original.payload))
    #expect(decoded == original)
  }

  @Test func aRingWithoutAccountStaysWithout() throws {
    let original = ring(expiresIn: 30, account: nil)
    #expect(original.payload["user_id"] == nil)
    #expect(try #require(CallRing(payload: original.payload)).accountUserId == nil)
  }

  @Test func aPayloadMissingTheRoomTheEventOrTheExpiryIsNoRing() {
    var payload = ring(expiresIn: 30).payload
    payload.removeValue(forKey: "room_id")
    #expect(CallRing(payload: payload) == nil)
    payload = ring(expiresIn: 30).payload
    payload["rtc_notification_event_id"] = ""
    #expect(CallRing(payload: payload) == nil)
    payload = ring(expiresIn: 30).payload
    payload.removeValue(forKey: "expires_at")
    #expect(CallRing(payload: payload) == nil)
  }

  @Test func theAccountIsAddedToARing() {
    let named = ring(expiresIn: 30, account: nil).with(accountUserId: "@me:a")
    #expect(named.accountUserId == "@me:a")
    #expect(named.eventId == "$ring")
  }
}
