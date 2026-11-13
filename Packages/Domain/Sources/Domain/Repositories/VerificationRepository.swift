import Foundation

/// Whether this session is verified, so other devices trust it and it can read older encrypted messages.
public enum DeviceVerificationState: Sendable, Equatable {
  case unknown
  case verified
  case unverified
}

/// One emoji of the short code both devices show.
public struct VerificationEmoji: Sendable, Equatable, Hashable {
  public let symbol: String
  public let name: String

  public init(symbol: String, name: String) {
    self.symbol = symbol
    self.name = name
  }
}

/// Where an emoji verification stands.
public enum VerificationStep: Sendable, Equatable {
  /// Another of the user's devices asks to verify this one.
  case incomingRequest(deviceName: String)
  /// This device asked; waiting for another device to accept.
  case waitingForOtherDevice
  /// Both devices agreed; the short code is being worked out.
  case starting
  /// Compare these with the other device.
  case emojis([VerificationEmoji])
  /// The other device cannot show emojis: compare these numbers.
  case numbers([Int])
  case verified
  case cancelled
  case failed
}

public enum VerificationError: Error, Sendable, Equatable {
  case notSignedIn
  case requestFailed
}

/// Emoji verification of this session with another of the user's devices. Implemented in MatrixData on the SDK's
/// session verification controller; no SDK type appears here (ADR 0006).
public protocol VerificationRepository: Sendable {
  func state() async -> DeviceVerificationState
  /// The steps of the current or next verification, started or received.
  func steps() async -> AsyncStream<VerificationStep>
  /// Asks the user's other devices to verify this one.
  func requestVerification() async throws(VerificationError)
  /// Accepts a request from another device.
  func acceptRequest() async throws(VerificationError)
  /// The emojis or numbers match.
  func confirm() async throws(VerificationError)
  /// The emojis or numbers do not match: the verification stops.
  func decline() async throws(VerificationError)
  func cancel() async
}

/// Why encrypted messages may not show on this device, as the Flutter chat warns (`ChatDeviceVerificationBanner`);
/// `nil` when nothing needs doing. The SDK reports trust for this session only, so the Flutter warning about another of
/// the user's sessions has no equivalent here.
public enum SessionWarning: Sendable, Equatable {
  /// This session is not verified: another of the user's devices can vouch for it.
  case unverified
  /// Chat backup is set up, but this session lacks its keys: the recovery key unlocks them.
  case recoveryIncomplete

  /// An unverified session comes first: verifying it also brings the keys.
  public static func of(verification: DeviceVerificationState, recovery: RecoveryStatus)
    -> SessionWarning?
  {
    if verification == .unverified { return .unverified }
    if recovery == .incomplete { return .recoveryIncomplete }
    return nil
  }
}
