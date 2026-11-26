import Testing

@testable import Domain

@Suite struct UndecryptableReasonTests {
  @Test func anUnknownCauseAdvisesVerifyingOnlyWhileUnverified() {
    #expect(
      UndecryptableReason.unknown.help(isDeviceVerified: false)
        == "Verify this device with your recovery key to read it.")
    #expect(
      UndecryptableReason.unknown.help(isDeviceVerified: true).hasPrefix("No key for this message"))
  }

  @Test func aKnownCauseSaysWhyNoKeyWillCome() {
    #expect(
      UndecryptableReason.sentBeforeJoining.help(isDeviceVerified: false)
        .contains("before you joined"))
    #expect(UndecryptableReason.withheld.help(isDeviceVerified: true).contains("did not share"))
  }

  @Test func aKeyWithheldFromAnUnverifiedDeviceAsksToVerifyUntilTheDeviceIsVerified() {
    #expect(
      UndecryptableReason.withheldFromUnverifiedDevice.help(isDeviceVerified: false)
        == "Verify this device with your recovery key to read it.")
    #expect(
      UndecryptableReason.withheldFromUnverifiedDevice.help(isDeviceVerified: true)
        .contains("did not share"))
  }
}
