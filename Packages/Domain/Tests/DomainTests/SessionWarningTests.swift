import Domain
import Testing

@Suite struct SessionWarningTests {
  @Test func anUnverifiedSessionIsWarnedFirst() {
    #expect(SessionWarning.of(verification: .unverified, recovery: .incomplete) == .unverified)
    #expect(SessionWarning.of(verification: .unverified, recovery: .enabled) == .unverified)
  }

  @Test func aVerifiedSessionWithoutItsKeysAsksForTheRecoveryKey() {
    #expect(
      SessionWarning.of(verification: .verified, recovery: .incomplete) == .recoveryIncomplete)
    #expect(SessionWarning.of(verification: .unknown, recovery: .incomplete) == .recoveryIncomplete)
  }

  @Test func nothingIsWarnedWhenTheSessionIsFineOrNotKnownYet() {
    #expect(SessionWarning.of(verification: .verified, recovery: .enabled) == nil)
    #expect(SessionWarning.of(verification: .verified, recovery: .disabled) == nil)
    #expect(SessionWarning.of(verification: .unknown, recovery: .unknown) == nil)
  }
}
