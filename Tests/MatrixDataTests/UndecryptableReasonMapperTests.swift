import Domain
import Foundation
import Testing

@testable import MatrixData

struct UndecryptableReasonMapperTests {
  @Test func aKeyWithheldBecauseThisDeviceWasUnverifiedIsToldApartFromOneTheSenderWithheld() {
    #expect(
      TimelineItemMapper.undecryptableReason(
        .megolmV1AesSha2(sessionId: "s", cause: .withheldForUnverifiedOrInsecureDevice))
        == .withheldFromUnverifiedDevice)
    #expect(
      TimelineItemMapper.undecryptableReason(
        .megolmV1AesSha2(sessionId: "s", cause: .withheldBySender))
        == .withheld)
  }
}
